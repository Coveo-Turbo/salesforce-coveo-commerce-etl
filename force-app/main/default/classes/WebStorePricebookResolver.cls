public with sharing class WebStorePricebookResolver {
  @TestVisible
  private static Map<Id, String> testPricebooksByWebStoreIds;
  @TestVisible
  private static Map<Id, Id> testStrikethroughPricebookIdByBuyerGroupId;

  public class PricebookResolution {
    public Set<Id> pricebookIds { get; private set; }
    public Map<Id, String> labelsByPricebookId { get; private set; }
    public Boolean isFiltered { get; private set; }

    private PricebookResolution(
      Set<Id> pricebookIds,
      Map<Id, String> labelsByPricebookId,
      Boolean isFiltered
    ) {
      this.pricebookIds = pricebookIds;
      this.labelsByPricebookId = labelsByPricebookId;
      this.isFiltered = isFiltered;
    }
  }

  public static PricebookResolution resolve(CatalogJobConfig__mdt jobConfig) {
    if (jobConfig != null && String.isNotBlank(jobConfig.PricebookIds__c)) {
      Set<Id> pricebookIds = parseIds(
        jobConfig.PricebookIds__c,
        'PricebookIds__c'
      );
      return new PricebookResolution(
        pricebookIds,
        buildRawLabels(pricebookIds),
        true
      );
    }

    if (jobConfig != null && String.isNotBlank(jobConfig.WebStoreIds__c)) {
      Set<Id> webStoreIds = parseIds(
        jobConfig.WebStoreIds__c,
        'WebStoreIds__c'
      );
      Map<Id, String> storeLabelsByPricebookId = resolvePricebooksByWebStoreIds(
        webStoreIds
      );
      Map<Id, String> labelsByPricebookId = buildRawLabels(
        storeLabelsByPricebookId.keySet()
      );

      return new PricebookResolution(
        new Set<Id>(storeLabelsByPricebookId.keySet()),
        labelsByPricebookId,
        true
      );
    }

    return new PricebookResolution(null, null, false);
  }

  public static Set<Id> resolveEffectivePricebookIds(
    CatalogJobConfig__mdt jobConfig
  ) {
    return resolve(jobConfig).pricebookIds;
  }

  public static Map<Id, String> resolvePricebookLabels(
    CatalogJobConfig__mdt jobConfig
  ) {
    return resolve(jobConfig).labelsByPricebookId;
  }

  public static Map<Id, String> resolvePricebooksByWebStoreIds(
    String webStoreIdsCsv
  ) {
    return resolvePricebooksByWebStoreIds(
      parseIds(webStoreIdsCsv, 'WebStoreIds__c')
    );
  }

  public static Map<Id, String> resolvePricebookNames(String pricebookIdsCsv) {
    return resolvePricebookNames(parseIds(pricebookIdsCsv, 'PricebookIds__c'));
  }

  public static Set<Id> resolveEffectiveWebStoreIds(
    CatalogJobConfig__mdt jobConfig
  ) {
    if (jobConfig == null) {
      return new Set<Id>();
    }
    if (String.isNotBlank(jobConfig.WebStoreIds__c)) {
      return parseIds(jobConfig.WebStoreIds__c, 'WebStoreIds__c');
    }
    if (String.isNotBlank(jobConfig.WebStoreId__c)) {
      return parseIds(jobConfig.WebStoreId__c, 'WebStoreId__c');
    }
    return new Set<Id>();
  }

  @TestVisible
  private static Set<Id> parseIds(String csv, String fieldName) {
    Set<Id> recordIds = new Set<Id>();
    if (String.isBlank(csv)) {
      return recordIds;
    }

    for (String rawValue : csv.split('[,;\\n\\r]+')) {
      String value = rawValue == null ? null : rawValue.trim();
      if (String.isBlank(value)) {
        continue;
      }
      try {
        recordIds.add((Id) value);
      } catch (Exception e) {
        throw new CatalogJobConfigException(
          fieldName + ' contains an invalid Salesforce ID: ' + value
        );
      }
    }
    return recordIds;
  }

  private static Map<Id, String> resolvePricebooksByWebStoreIds(
    Set<Id> webStoreIds
  ) {
    Map<Id, String> labelsByPricebookId = new Map<Id, String>();
    if (webStoreIds == null || webStoreIds.isEmpty()) {
      return labelsByPricebookId;
    }

    if (Test.isRunningTest() && testPricebooksByWebStoreIds != null) {
      labelsByPricebookId.putAll(testPricebooksByWebStoreIds);
      return labelsByPricebookId;
    }

    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    requireFields(
      globalDescribe,
      'WebStorePricebook',
      new Set<String>{ 'WebStoreId', 'Pricebook2Id', 'IsActive' }
    );
    requireFields(
      globalDescribe,
      'WebStoreBuyerGroup',
      new Set<String>{ 'WebStoreId', 'BuyerGroupId' }
    );
    requireFields(
      globalDescribe,
      'BuyerGroupPricebook',
      new Set<String>{ 'BuyerGroupId', 'Pricebook2Id', 'IsActive' }
    );

    Map<Id, Set<Id>> storeIdsByPricebookId = new Map<Id, Set<Id>>();
    for (
      SObject junction : Database.query(
        'SELECT WebStoreId, Pricebook2Id FROM WebStorePricebook ' +
        'WHERE WebStoreId IN :webStoreIds AND Pricebook2Id != NULL ' +
        'AND IsActive = TRUE'
      )
    ) {
      Id webStoreId = (Id) junction.get('WebStoreId');
      Id pricebookId = (Id) junction.get('Pricebook2Id');
      addPricebookStoreScope(
        storeIdsByPricebookId,
        pricebookId,
        new Set<Id>{ webStoreId }
      );
    }

    Map<Id, Set<Id>> storeIdsByBuyerGroupId = new Map<Id, Set<Id>>();
    for (
      SObject junction : Database.query(
        'SELECT WebStoreId, BuyerGroupId FROM WebStoreBuyerGroup ' +
        'WHERE WebStoreId IN :webStoreIds AND BuyerGroupId != NULL'
      )
    ) {
      Id webStoreId = (Id) junction.get('WebStoreId');
      Id buyerGroupId = (Id) junction.get('BuyerGroupId');
      if (!storeIdsByBuyerGroupId.containsKey(buyerGroupId)) {
        storeIdsByBuyerGroupId.put(buyerGroupId, new Set<Id>());
      }
      storeIdsByBuyerGroupId.get(buyerGroupId).add(webStoreId);
    }

    Set<Id> buyerGroupIds = storeIdsByBuyerGroupId.keySet();
    if (!buyerGroupIds.isEmpty()) {
      Map<Id, Id> strikethroughPricebookIdByBuyerGroupId = resolveStrikethroughPricebookIds(
        globalDescribe,
        buyerGroupIds
      );
      for (
        SObject junction : Database.query(
          'SELECT BuyerGroupId, Pricebook2Id FROM BuyerGroupPricebook ' +
          'WHERE BuyerGroupId IN :buyerGroupIds AND Pricebook2Id != NULL ' +
          'AND IsActive = TRUE'
        )
      ) {
        Id buyerGroupId = (Id) junction.get('BuyerGroupId');
        Id pricebookId = (Id) junction.get('Pricebook2Id');
        if (
          isStrikethroughPricebook(
            buyerGroupId,
            pricebookId,
            strikethroughPricebookIdByBuyerGroupId
          )
        ) {
          continue;
        }
        addPricebookStoreScope(
          storeIdsByPricebookId,
          pricebookId,
          storeIdsByBuyerGroupId.get(buyerGroupId)
        );
      }
    }

    Set<Id> matchedWebStoreIds = new Set<Id>();
    for (Set<Id> pricebookStoreIds : storeIdsByPricebookId.values()) {
      matchedWebStoreIds.addAll(pricebookStoreIds);
    }

    Map<Id, String> storeNamesById = new Map<Id, String>();
    if (
      !matchedWebStoreIds.isEmpty() && globalDescribe.containsKey('WebStore')
    ) {
      for (
        SObject webStore : Database.query(
          'SELECT Id, Name FROM WebStore WHERE Id IN :matchedWebStoreIds'
        )
      ) {
        storeNamesById.put(
          (Id) webStore.get('Id'),
          String.valueOf(webStore.get('Name'))
        );
      }
    }

    for (Id pricebookId : storeIdsByPricebookId.keySet()) {
      List<String> storeLabels = new List<String>();
      for (Id webStoreId : storeIdsByPricebookId.get(pricebookId)) {
        storeLabels.add(
          storeNamesById.containsKey(webStoreId)
            ? storeNamesById.get(webStoreId)
            : String.valueOf(webStoreId)
        );
      }
      storeLabels.sort();
      labelsByPricebookId.put(pricebookId, String.join(storeLabels, '+'));
    }

    return labelsByPricebookId;
  }

  private static void requireFields(
    Map<String, Schema.SObjectType> globalDescribe,
    String objectName,
    Set<String> requiredFieldNames
  ) {
    if (!globalDescribe.containsKey(objectName)) {
      throw new CatalogJobConfigException(
        'WebStoreIds__c requires the B2B Commerce ' + objectName + ' object.'
      );
    }

    Map<String, Schema.SObjectField> fieldsByName = globalDescribe
      .get(objectName)
      .getDescribe()
      .fields.getMap();
    for (String fieldName : requiredFieldNames) {
      if (!fieldsByName.containsKey(fieldName)) {
        throw new CatalogJobConfigException(
          objectName + ' does not expose the required ' + fieldName + ' field.'
        );
      }
    }
  }

  private static void addPricebookStoreScope(
    Map<Id, Set<Id>> storeIdsByPricebookId,
    Id pricebookId,
    Set<Id> webStoreIds
  ) {
    if (
      pricebookId == null ||
      webStoreIds == null ||
      webStoreIds.isEmpty()
    ) {
      return;
    }
    if (!storeIdsByPricebookId.containsKey(pricebookId)) {
      storeIdsByPricebookId.put(pricebookId, new Set<Id>());
    }
    storeIdsByPricebookId.get(pricebookId).addAll(webStoreIds);
  }

  private static Map<Id, Id> resolveStrikethroughPricebookIds(
    Map<String, Schema.SObjectType> globalDescribe,
    Set<Id> buyerGroupIds
  ) {
    Map<Id, Id> pricebookIdByBuyerGroupId = new Map<Id, Id>();
    if (
      Test.isRunningTest() &&
      testStrikethroughPricebookIdByBuyerGroupId != null
    ) {
      pricebookIdByBuyerGroupId.putAll(
        testStrikethroughPricebookIdByBuyerGroupId
      );
      return pricebookIdByBuyerGroupId;
    }
    if (
      buyerGroupIds == null ||
      buyerGroupIds.isEmpty() ||
      !globalDescribe.containsKey('BuyerGroup')
    ) {
      return pricebookIdByBuyerGroupId;
    }

    Map<String, Schema.SObjectField> buyerGroupFields = globalDescribe
      .get('BuyerGroup')
      .getDescribe()
      .fields.getMap();
    if (!buyerGroupFields.containsKey('StrikethroughPricebookId')) {
      return pricebookIdByBuyerGroupId;
    }

    for (
      SObject buyerGroup : Database.query(
        'SELECT Id, StrikethroughPricebookId FROM BuyerGroup ' +
        'WHERE Id IN :buyerGroupIds AND StrikethroughPricebookId != NULL'
      )
    ) {
      pricebookIdByBuyerGroupId.put(
        (Id) buyerGroup.get('Id'),
        (Id) buyerGroup.get('StrikethroughPricebookId')
      );
    }
    return pricebookIdByBuyerGroupId;
  }

  @TestVisible
  private static Boolean isStrikethroughPricebook(
    Id buyerGroupId,
    Id pricebookId,
    Map<Id, Id> strikethroughPricebookIdByBuyerGroupId
  ) {
    return strikethroughPricebookIdByBuyerGroupId != null &&
      strikethroughPricebookIdByBuyerGroupId.get(buyerGroupId) == pricebookId;
  }

  private static Map<Id, String> resolvePricebookNames(Set<Id> pricebookIds) {
    Map<Id, String> namesByPricebookId = new Map<Id, String>();
    if (pricebookIds == null || pricebookIds.isEmpty()) {
      return namesByPricebookId;
    }

    for (Pricebook2 pricebook : [
      SELECT Id, Name
      FROM Pricebook2
      WHERE Id IN :pricebookIds
    ]) {
      namesByPricebookId.put(pricebook.Id, pricebook.Name);
    }

    for (Id pricebookId : pricebookIds) {
      if (!namesByPricebookId.containsKey(pricebookId)) {
        namesByPricebookId.put(pricebookId, String.valueOf(pricebookId));
      }
    }
    return namesByPricebookId;
  }

  private static Map<Id, String> buildRawLabels(Set<Id> pricebookIds) {
    Map<Id, String> labelsByPricebookId = new Map<Id, String>();
    if (pricebookIds == null) {
      return labelsByPricebookId;
    }
    for (Id pricebookId : pricebookIds) {
      labelsByPricebookId.put(pricebookId, String.valueOf(pricebookId));
    }
    return labelsByPricebookId;
  }
}
