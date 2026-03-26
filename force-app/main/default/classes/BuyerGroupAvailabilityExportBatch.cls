global with sharing class BuyerGroupAvailabilityExportBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
  private final CatalogJobConfig__mdt jobConfig;

  public Long firstOrderingId;

  public BuyerGroupAvailabilityExportBatch(String jobConfigDeveloperName) {
    List<CatalogJobConfig__mdt> configs = [
      SELECT
        DeveloperName,
        Label,
        CoveoOrgId__c,
        SourceId__c,
        AvailabilitySourceId__c,
        WebStoreId__c,
        Locale__c,
        IsActive__c,
        ProductFilter__c,
        BuilderType__c,
        CatalogId__c,
        BatchSize__c,
        EnablePayloadLogging__c,
        EnableBuyerGroupAvailability__c
      FROM CatalogJobConfig__mdt
      WHERE DeveloperName = :jobConfigDeveloperName
      LIMIT 1
    ];

    if (configs.isEmpty()) {
      throw new CatalogJobException(
        'No CatalogJobConfig__mdt record found with DeveloperName: ' +
        jobConfigDeveloperName
      );
    }

    this.jobConfig = configs[0];
    validateConfig();
  }

  public Integer getBatchSize() {
    if (jobConfig.BatchSize__c != null) {
      return Integer.valueOf(jobConfig.BatchSize__c);
    }
    return 50;
  }

  global Database.QueryLocator start(Database.BatchableContext bc) {
    Set<Id> buyerGroupIds = getBuyerGroupIdsForWebStore(
      jobConfig.WebStoreId__c
    );

    if (buyerGroupIds.isEmpty()) {
      throw new CatalogJobConfigException(
        'No BuyerGroup records found for WebStoreId__c ' +
        jobConfig.WebStoreId__c
      );
    }

    String query =
      'SELECT Id, Name FROM BuyerGroup WHERE Id IN (' +
      buildIdInClause(buyerGroupIds) +
      ') ORDER BY Name';
    return Database.getQueryLocator(query);
  }

  global void execute(Database.BatchableContext bc, List<SObject> scope) {
    Set<Id> buyerGroupIds = new Set<Id>();
    for (SObject buyerGroup : scope) {
      buyerGroupIds.add((Id) buyerGroup.get('Id'));
    }

    Map<Id, Set<Id>> visiblePolicyIdsByBuyerGroup = getVisiblePolicyIdsByBuyerGroup(
      buyerGroupIds
    );
    Map<Id, Set<String>> exportedItemIdsByBuyerGroup = getExportedItemIdsByBuyerGroup(
      visiblePolicyIdsByBuyerGroup
    );

    String ndjsonPayload = BuyerGroupAvailabilityPayloadBuilder.buildFullUpdateNdjson(
      scope,
      exportedItemIdsByBuyerGroup,
      jobConfig.WebStoreId__c
    );

    CoveoPayloadValidator.Result vr = CoveoPayloadValidator.validate(
      ndjsonPayload
    );
    Blob ndjson = Blob.valueOf(ndjsonPayload);

    CoveoStreamClient client = new CoveoStreamClient(
      jobConfig.CoveoOrgId__c,
      jobConfig.AvailabilitySourceId__c
    );
    Map<String, Object> container = client.createFileContainer();
    client.uploadNdjson(
      (String) container.get('uploadUri'),
      (Map<String, Object>) container.get('requiredHeaders'),
      ndjson
    );

    String updateResponse = client.streamUpdate(
      (String) container.get('fileId')
    );
    Map<String, Object> resMap = (Map<String, Object>) JSON.deserializeUntyped(
      updateResponse
    );

    if (resMap.containsKey('orderingId') && resMap.get('orderingId') != null) {
      Long oid = Long.valueOf(String.valueOf(resMap.get('orderingId')));
      if (firstOrderingId == null) {
        firstOrderingId = oid;
      }
    }

    if (jobConfig.EnablePayloadLogging__c == true) {
      Coveo_Payload_Log__c log = new Coveo_Payload_Log__c(
        ScopeSize__c = scope.size(),
        OperationCount__c = vr.operationCount,
        IsValid__c = vr.isValid,
        Reason__c = vr.reason,
        Payload__c = ndjsonPayload.left(32000)
      );

      System.enqueueJob(
        new CoveoPayloadLogQueueable(new List<Coveo_Payload_Log__c>{ log })
      );
    }
  }

  global void finish(Database.BatchableContext bc) {
    if (firstOrderingId == null) {
      return;
    }

    CoveoDeleteOlderThan.deleteOlderThan(
      jobConfig.CoveoOrgId__c,
      jobConfig.AvailabilitySourceId__c,
      firstOrderingId
    );
  }

  private void validateConfig() {
    if (jobConfig.EnableBuyerGroupAvailability__c != true) {
      throw new CatalogJobConfigException(
        'EnableBuyerGroupAvailability__c must be true to run BuyerGroupAvailabilityExportBatch.'
      );
    }

    if (String.isBlank(jobConfig.AvailabilitySourceId__c)) {
      throw new CatalogJobConfigException(
        'AvailabilitySourceId__c is required when Buyer Group availability export is enabled.'
      );
    }

    if (String.isBlank(jobConfig.WebStoreId__c)) {
      throw new CatalogJobConfigException(
        'WebStoreId__c is required when Buyer Group availability export is enabled.'
      );
    }
  }

  private static Set<Id> getBuyerGroupIdsForWebStore(String webStoreId) {
    Set<Id> buyerGroupIds = new Set<Id>();

    String query =
      'SELECT BuyerGroupId FROM WebStoreBuyerGroup WHERE WebStoreId = \'' +
      String.escapeSingleQuotes(webStoreId) +
      '\' AND BuyerGroupId != NULL';

    for (SObject link : Database.query(query)) {
      buyerGroupIds.add((Id) link.get('BuyerGroupId'));
    }

    return buyerGroupIds;
  }

  private static String buildIdInClause(Set<Id> recordIds) {
    List<String> tokens = new List<String>();
    for (Id recordId : recordIds) {
      tokens.add(
        '\'' + String.escapeSingleQuotes(String.valueOf(recordId)) + '\''
      );
    }
    return String.join(tokens, ',');
  }

  @TestVisible
  private Map<Id, Set<Id>> getVisiblePolicyIdsByBuyerGroup(
    Set<Id> buyerGroupIds
  ) {
    Map<Id, Set<Id>> policyIdsByBuyerGroup = new Map<Id, Set<Id>>();

    if (buyerGroupIds.isEmpty()) {
      return policyIdsByBuyerGroup;
    }

    List<SObject> links = Database.query(
      'SELECT PolicyId, BuyerGroupId FROM CommerceEntitlementBuyerGroup WHERE BuyerGroupId IN (' +
        buildIdInClause(buyerGroupIds) +
        ') AND PolicyId != NULL'
    );

    Set<Id> policyIds = new Set<Id>();
    for (SObject link : links) {
      policyIds.add((Id) link.get('PolicyId'));
    }

    Set<Id> visiblePolicyIds = new Set<Id>();
    if (!policyIds.isEmpty()) {
      for (
        SObject policy : Database.query(
          'SELECT Id FROM CommerceEntitlementPolicy WHERE Id IN (' +
            buildIdInClause(policyIds) +
            ') AND CanViewProduct = TRUE'
        )
      ) {
        visiblePolicyIds.add((Id) policy.get('Id'));
      }
    }

    for (SObject link : links) {
      Id policyId = (Id) link.get('PolicyId');
      Id buyerGroupId = (Id) link.get('BuyerGroupId');

      if (!visiblePolicyIds.contains(policyId)) {
        continue;
      }

      if (!policyIdsByBuyerGroup.containsKey(buyerGroupId)) {
        policyIdsByBuyerGroup.put(buyerGroupId, new Set<Id>());
      }
      policyIdsByBuyerGroup.get(buyerGroupId).add(policyId);
    }

    return policyIdsByBuyerGroup;
  }

  @TestVisible
  private Map<Id, Set<String>> getExportedItemIdsByBuyerGroup(
    Map<Id, Set<Id>> policyIdsByBuyerGroup
  ) {
    Map<Id, Set<String>> itemIdsByBuyerGroup = new Map<Id, Set<String>>();

    if (policyIdsByBuyerGroup.isEmpty()) {
      return itemIdsByBuyerGroup;
    }

    Map<Id, Set<Id>> buyerGroupIdsByPolicy = new Map<Id, Set<Id>>();
    Set<Id> policyIds = new Set<Id>();

    for (Id buyerGroupId : policyIdsByBuyerGroup.keySet()) {
      for (Id policyId : policyIdsByBuyerGroup.get(buyerGroupId)) {
        policyIds.add(policyId);
        if (!buyerGroupIdsByPolicy.containsKey(policyId)) {
          buyerGroupIdsByPolicy.put(policyId, new Set<Id>());
        }
        buyerGroupIdsByPolicy.get(policyId).add(buyerGroupId);
      }
    }

    Set<Id> productIds = new Set<Id>();
    Map<Id, Set<Id>> rawProductIdsByBuyerGroup = new Map<Id, Set<Id>>();

    for (
      SObject link : Database.query(
        'SELECT PolicyId, ProductId FROM CommerceEntitlementProduct WHERE PolicyId IN (' +
          buildIdInClause(policyIds) +
          ') AND ProductId != NULL'
      )
    ) {
      Id policyId = (Id) link.get('PolicyId');
      Id productId = (Id) link.get('ProductId');

      productIds.add(productId);

      Set<Id> linkedBuyerGroupIds = buyerGroupIdsByPolicy.get(policyId);
      if (linkedBuyerGroupIds == null) {
        continue;
      }

      for (Id buyerGroupId : linkedBuyerGroupIds) {
        if (!rawProductIdsByBuyerGroup.containsKey(buyerGroupId)) {
          rawProductIdsByBuyerGroup.put(buyerGroupId, new Set<Id>());
        }
        rawProductIdsByBuyerGroup.get(buyerGroupId).add(productId);
      }
    }

    Map<Id, String> exportedItemIdByProductId = new Map<Id, String>();
    for (
      Product2 product : CatalogJobScopeUtil.queryProductsByIds(
        jobConfig,
        productIds,
        new List<String>{ 'Id', 'ProductCode' }
      )
    ) {
      exportedItemIdByProductId.put(
        product.Id,
        CatalogJobScopeUtil.getExportedItemId(product)
      );
    }

    for (Id buyerGroupId : rawProductIdsByBuyerGroup.keySet()) {
      Set<String> exportedIds = new Set<String>();
      for (Id productId : rawProductIdsByBuyerGroup.get(buyerGroupId)) {
        if (exportedItemIdByProductId.containsKey(productId)) {
          exportedIds.add(exportedItemIdByProductId.get(productId));
        }
      }
      itemIdsByBuyerGroup.put(buyerGroupId, exportedIds);
    }

    return itemIdsByBuyerGroup;
  }
}
