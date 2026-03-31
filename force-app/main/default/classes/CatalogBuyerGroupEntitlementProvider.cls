public with sharing class CatalogBuyerGroupEntitlementProvider
  implements ICatalogBuyerGroupAccessProvider {
  public List<String> getRequiredProductFieldsForBuyerGroupAccess() {
    return new List<String>();
  }

  public Map<Id, CatalogBuyerGroupAccessSnapshot> resolveBuyerGroupAccess(
    CatalogJobConfig__mdt jobConfig,
    List<Product2> products,
    Map<Id, String> ecProductIdByProductId
  ) {
    Map<Id, CatalogBuyerGroupAccessSnapshot> snapshotsByProductId =
      new Map<Id, CatalogBuyerGroupAccessSnapshot>();

    if (
      !hasCommerceAvailabilitySchema() ||
      jobConfig == null ||
      String.isBlank(jobConfig.WebStoreId__c) ||
      products == null ||
      products.isEmpty()
    ) {
      return snapshotsByProductId;
    }

    Set<Id> productIds = new Set<Id>();
    for (Product2 product : products) {
      if (
        product != null &&
        product.Id != null &&
        ecProductIdByProductId != null &&
        ecProductIdByProductId.containsKey(product.Id)
      ) {
        productIds.add(product.Id);
      }
    }

    if (productIds.isEmpty()) {
      return snapshotsByProductId;
    }

    Set<Id> buyerGroupIds = getBuyerGroupIdsForWebStore(jobConfig.WebStoreId__c);
    if (buyerGroupIds.isEmpty()) {
      return snapshotsByProductId;
    }

    Map<Id, String> buyerGroupNameById = getBuyerGroupNameById(buyerGroupIds);
    Map<Id, Set<Id>> visiblePolicyIdsByBuyerGroup =
      getVisiblePolicyIdsByBuyerGroup(buyerGroupIds);

    if (visiblePolicyIdsByBuyerGroup.isEmpty()) {
      return snapshotsByProductId;
    }

    Map<Id, Set<Id>> buyerGroupIdsByPolicy = new Map<Id, Set<Id>>();
    Set<Id> policyIds = new Set<Id>();

    for (Id buyerGroupId : visiblePolicyIdsByBuyerGroup.keySet()) {
      for (Id policyId : visiblePolicyIdsByBuyerGroup.get(buyerGroupId)) {
        policyIds.add(policyId);
        if (!buyerGroupIdsByPolicy.containsKey(policyId)) {
          buyerGroupIdsByPolicy.put(policyId, new Set<Id>());
        }
        buyerGroupIdsByPolicy.get(policyId).add(buyerGroupId);
      }
    }

    if (policyIds.isEmpty()) {
      return snapshotsByProductId;
    }

    for (
      SObject link : Database.query(
        'SELECT PolicyId, ProductId FROM CommerceEntitlementProduct WHERE PolicyId IN (' +
          buildIdInClause(policyIds) +
          ') AND ProductId IN (' +
          buildIdInClause(productIds) +
          ') AND ProductId != NULL'
      )
    ) {
      Id policyId = (Id) link.get('PolicyId');
      Id productId = (Id) link.get('ProductId');

      if (!buyerGroupIdsByPolicy.containsKey(policyId)) {
        continue;
      }

      CatalogBuyerGroupAccessSnapshot snapshot = getOrCreateSnapshot(
        snapshotsByProductId,
        productId,
        ecProductIdByProductId,
        jobConfig.WebStoreId__c
      );

      for (Id buyerGroupId : buyerGroupIdsByPolicy.get(policyId)) {
        snapshot.buyerGroupIds.add(String.valueOf(buyerGroupId));

        String buyerGroupName = buyerGroupNameById.get(buyerGroupId);
        if (String.isNotBlank(buyerGroupName)) {
          snapshot.buyerGroupNames.add(buyerGroupName);
        }
      }
    }

    return snapshotsByProductId;
  }

  private static CatalogBuyerGroupAccessSnapshot getOrCreateSnapshot(
    Map<Id, CatalogBuyerGroupAccessSnapshot> snapshotsByProductId,
    Id productId,
    Map<Id, String> ecProductIdByProductId,
    String webStoreId
  ) {
    if (!snapshotsByProductId.containsKey(productId)) {
      snapshotsByProductId.put(
        productId,
        CatalogBuyerGroupAccessResolver.createEmptySnapshot(
          productId,
          ecProductIdByProductId.get(productId),
          webStoreId
        )
      );
    }

    return snapshotsByProductId.get(productId);
  }

  private static Boolean hasCommerceAvailabilitySchema() {
    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    return globalDescribe.containsKey('BuyerGroup') &&
      globalDescribe.containsKey('WebStoreBuyerGroup') &&
      globalDescribe.containsKey('CommerceEntitlementPolicy') &&
      globalDescribe.containsKey('CommerceEntitlementBuyerGroup') &&
      globalDescribe.containsKey('CommerceEntitlementProduct');
  }

  private static Set<Id> getBuyerGroupIdsForWebStore(String webStoreId) {
    Set<Id> buyerGroupIds = new Set<Id>();

    if (String.isBlank(webStoreId)) {
      return buyerGroupIds;
    }

    for (
      SObject link : Database.query(
        'SELECT BuyerGroupId FROM WebStoreBuyerGroup WHERE WebStoreId = \'' +
          String.escapeSingleQuotes(webStoreId) +
          '\' AND BuyerGroupId != NULL'
      )
    ) {
      buyerGroupIds.add((Id) link.get('BuyerGroupId'));
    }

    return buyerGroupIds;
  }

  private static Map<Id, String> getBuyerGroupNameById(Set<Id> buyerGroupIds) {
    Map<Id, String> buyerGroupNameById = new Map<Id, String>();

    if (buyerGroupIds == null || buyerGroupIds.isEmpty()) {
      return buyerGroupNameById;
    }

    for (
      SObject buyerGroup : Database.query(
        'SELECT Id, Name FROM BuyerGroup WHERE Id IN (' +
          buildIdInClause(buyerGroupIds) +
          ')'
      )
    ) {
      buyerGroupNameById.put(
        (Id) buyerGroup.get('Id'),
        String.valueOf(buyerGroup.get('Name'))
      );
    }

    return buyerGroupNameById;
  }

  private static Map<Id, Set<Id>> getVisiblePolicyIdsByBuyerGroup(
    Set<Id> buyerGroupIds
  ) {
    Map<Id, Set<Id>> policyIdsByBuyerGroup = new Map<Id, Set<Id>>();

    if (buyerGroupIds == null || buyerGroupIds.isEmpty()) {
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

  private static String buildIdInClause(Set<Id> recordIds) {
    List<String> tokens = new List<String>();
    for (Id recordId : recordIds) {
      tokens.add(
        '\'' + String.escapeSingleQuotes(String.valueOf(recordId)) + '\''
      );
    }
    return String.join(tokens, ',');
  }
}
