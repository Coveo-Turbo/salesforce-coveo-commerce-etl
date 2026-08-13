public with sharing class CatalogProductExportSupport {
  private static final Map<String, SObjectField> PRODUCT_FIELDS = Product2.SObjectType
    .getDescribe()
    .fields.getMap();

  public class StreamResult {
    public Long orderingId { get; set; }
    public String responseBody { get; set; }
  }

  public static List<String> parseExtraFieldNames(
    String additionalProductFields
  ) {
    List<String> fieldNames = new List<String>();

    if (String.isBlank(additionalProductFields)) {
      return fieldNames;
    }

    for (String fieldName : additionalProductFields.split(',')) {
      addFieldIfMissing(fieldNames, fieldName);
    }

    return fieldNames;
  }

  public static List<String> getRequiredProductFields(
    CatalogJobConfig__mdt jobConfig
  ) {
    ICatalogJsonBuilder builder = CatalogProductIdentityResolver.getBuilder(
      jobConfig
    );
    List<String> fields = new List<String>{
      'Id',
      'Name',
      'StockKeepingUnit',
      'Family',
      'ProductCode',
      'Description',
      'QuantityUnitOfMeasure',
      'IsActive',
      'Type',
      'DisplayUrl'
    };

    for (
      String fieldName : CatalogProductIdentityResolver.getRequiredProductFields(
        builder
      )
    ) {
      addFieldIfMissing(fields, fieldName);
    }

    addBuilderRelationshipFields(fields, builder);

    if (CatalogBuyerGroupAvailabilityMode.usesEmbedded(jobConfig)) {
      for (
        String fieldName : CatalogBuyerGroupAccessResolver.getRequiredProductFields(
          builder
        )
      ) {
        addFieldIfMissing(fields, fieldName);
      }
    }

    return fields;
  }

  public static Map<Id, Map<String, Decimal>> loadPricesByProduct(
    List<Product2> scope,
    Id stdPricebookId
  ) {
    return loadPricesByProduct(scope, stdPricebookId, null, null);
  }

  public static Map<Id, Map<String, Decimal>> loadPricesByProduct(
    List<Product2> scope,
    Id stdPricebookId,
    Set<Id> targetPricebookIds
  ) {
    return loadPricesByProduct(scope, stdPricebookId, targetPricebookIds, null);
  }

  public static Map<Id, Map<String, Decimal>> loadPricesByProduct(
    List<Product2> scope,
    Id stdPricebookId,
    Set<Id> targetPricebookIds,
    Map<Id, String> labelsByPricebookId
  ) {
    Map<Id, Map<String, Decimal>> pricesByProduct = new Map<Id, Map<String, Decimal>>();

    if (
      scope == null ||
      scope.isEmpty() ||
      (targetPricebookIds != null && targetPricebookIds.isEmpty())
    ) {
      return pricesByProduct;
    }

    List<PricebookEntry> entries = targetPricebookIds == null
      ? [
          SELECT Id, Product2Id, Pricebook2Id, UnitPrice, ProductSellingModelId
          FROM PricebookEntry
          WHERE Product2Id IN :scope AND IsActive = TRUE AND UnitPrice != NULL
          ORDER BY Product2Id, Pricebook2Id, ProductSellingModelId, Id
        ]
      : [
          SELECT Id, Product2Id, Pricebook2Id, UnitPrice, ProductSellingModelId
          FROM PricebookEntry
          WHERE
            Product2Id IN :scope
            AND Pricebook2Id IN :targetPricebookIds
            AND IsActive = TRUE
            AND UnitPrice != NULL
          ORDER BY Product2Id, Pricebook2Id, ProductSellingModelId, Id
        ];

    for (PricebookEntry pricebookEntry : entries) {
      if (pricebookEntry.Product2Id == null) {
        continue;
      }

      if (!pricesByProduct.containsKey(pricebookEntry.Product2Id)) {
        pricesByProduct.put(
          pricebookEntry.Product2Id,
          new Map<String, Decimal>()
        );
      }

      String basePriceKey = labelsByPricebookId != null &&
        labelsByPricebookId.containsKey(pricebookEntry.Pricebook2Id)
        ? labelsByPricebookId.get(pricebookEntry.Pricebook2Id)
        : (pricebookEntry.Pricebook2Id == stdPricebookId)
            ? ''
            : String.valueOf(pricebookEntry.Pricebook2Id);
      Map<String, Decimal> productPrices = pricesByProduct.get(
        pricebookEntry.Product2Id
      );
      String priceKey = buildUniquePriceKey(
        productPrices,
        basePriceKey,
        pricebookEntry.ProductSellingModelId,
        pricebookEntry.Pricebook2Id,
        pricebookEntry.Id
      );
      productPrices.put(priceKey, pricebookEntry.UnitPrice);
    }

    return pricesByProduct;
  }

  @TestVisible
  private static String buildUniquePriceKey(
    Map<String, Decimal> existingPrices,
    String basePriceKey,
    Id productSellingModelId,
    Id pricebookId,
    Id pricebookEntryId
  ) {
    Set<String> normalizedExistingKeys = new Set<String>();
    for (String existingKey : existingPrices.keySet()) {
      normalizedExistingKeys.add(existingKey.toLowerCase());
    }

    String sellingModelSuffix = productSellingModelId == null
      ? ''
      : ':' + String.valueOf(productSellingModelId);
    String candidate = basePriceKey + sellingModelSuffix;
    Integer collisionAttempt = 0;
    while (normalizedExistingKeys.contains(candidate.toLowerCase())) {
      collisionAttempt++;
      String disambiguator = collisionAttempt == 1
        ? String.valueOf(pricebookId)
        : String.valueOf(pricebookId) +
          ':' +
          String.valueOf(pricebookEntryId) +
          (collisionAttempt > 2 ? ':' + collisionAttempt : '');
      candidate =
        basePriceKey +
        ' [' +
        disambiguator +
        ']' +
        sellingModelSuffix;
    }
    return candidate;
  }

  public static String buildFullUpdatePayload(
    CatalogJobConfig__mdt jobConfig,
    List<Product2> scope,
    Map<Id, Map<String, Decimal>> pricesByProduct,
    List<String> extraFieldNames
  ) {
    ICatalogJsonBuilder builder = CatalogJsonBuilderFactory.getForBuilderType(
      jobConfig.BuilderType__c
    );
    String ndjsonPayload = builder.buildFullUpdateNdjson(
      scope,
      pricesByProduct,
      extraFieldNames
    );

    if (CatalogBuyerGroupAvailabilityMode.usesEmbedded(jobConfig)) {
      Map<Id, CatalogBuyerGroupAccessSnapshot> snapshotsByProductId = CatalogBuyerGroupAccessResolver.resolveBuyerGroupAccess(
        jobConfig,
        scope,
        builder
      );
      Set<Id> effectiveWebStoreIds = WebStorePricebookResolver.resolveEffectiveWebStoreIds(
        jobConfig
      );
      ndjsonPayload = CatalogBuyerGroupPayloadDecorator.decorateFullUpdatePayload(
        ndjsonPayload,
        snapshotsByProductId,
        effectiveWebStoreIds
      );
    }

    return ndjsonPayload;
  }

  public static StreamResult streamPayload(
    CatalogJobConfig__mdt jobConfig,
    String ndjsonPayload
  ) {
    CoveoStreamClient client = new CoveoStreamClient(
      jobConfig.CoveoOrgId__c,
      jobConfig.SourceId__c
    );
    Map<String, Object> container = client.createFileContainer();
    client.uploadNdjson(
      (String) container.get('uploadUri'),
      (Map<String, Object>) container.get('requiredHeaders'),
      Blob.valueOf(ndjsonPayload)
    );

    StreamResult result = new StreamResult();
    result.responseBody = client.streamUpdate((String) container.get('fileId'));

    Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(
      result.responseBody
    );
    if (
      response != null &&
      response.containsKey('orderingId') &&
      response.get('orderingId') != null
    ) {
      result.orderingId = Long.valueOf(
        String.valueOf(response.get('orderingId'))
      );
    }

    return result;
  }

  public static void enqueuePayloadLogIfEnabled(
    CatalogJobConfig__mdt jobConfig,
    Integer scopeSize,
    CoveoPayloadValidator.Result validationResult,
    String ndjsonPayload
  ) {
    if (jobConfig.EnablePayloadLogging__c != true) {
      return;
    }

    Coveo_Payload_Log__c log = new Coveo_Payload_Log__c(
      ScopeSize__c = scopeSize,
      OperationCount__c = validationResult.operationCount,
      IsValid__c = validationResult.isValid,
      Reason__c = validationResult.reason,
      Payload__c = ndjsonPayload.left(32000)
    );

    System.enqueueJob(
      new CoveoPayloadLogQueueable(new List<Coveo_Payload_Log__c>{ log })
    );
  }

  @TestVisible
  private static void addBuilderRelationshipFields(
    List<String> fields,
    ICatalogJsonBuilder builder
  ) {
    if (builder instanceof CatalogJsonBuilderGrouping) {
      addFieldIfPresent(fields, 'Parent_Product__c');
      return;
    }

    if (builder instanceof CatalogJsonBuilderVariant) {
      addFieldIfPresent(fields, 'Parent_Product__c');
      addFieldIfPresent(fields, 'Type');
      return;
    }

    if (builder instanceof CatalogJsonBuilderGroupingWithVariants) {
      addFieldIfPresent(fields, 'Parent_Product__c');
      addFieldIfPresent(fields, 'Product_Group__c');
      addFieldIfPresent(fields, 'Type');
    }
  }

  @TestVisible
  private static void addFieldIfPresent(List<String> fields, String fieldName) {
    if (PRODUCT_FIELDS.containsKey(fieldName)) {
      addFieldIfMissing(fields, fieldName);
    }
  }

  @TestVisible
  private static void addFieldIfMissing(List<String> fields, String fieldName) {
    if (String.isBlank(fieldName) || fields == null) {
      return;
    }

    String trimmedField = fieldName.trim();
    if (String.isNotBlank(trimmedField) && !fields.contains(trimmedField)) {
      fields.add(trimmedField);
    }
  }
}
