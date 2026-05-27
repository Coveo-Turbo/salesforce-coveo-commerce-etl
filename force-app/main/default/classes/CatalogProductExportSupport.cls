public with sharing class CatalogProductExportSupport {
  private static final Map<String, SObjectField> PRODUCT_FIELDS = Product2.SObjectType
    .getDescribe()
    .fields.getMap();

  public class StreamResult {
    public Long orderingId { get; set; }
    public String responseBody { get; set; }
  }

  public static List<String> parseExtraFieldNames(String additionalProductFields) {
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
    Map<Id, Map<String, Decimal>> pricesByProduct =
      new Map<Id, Map<String, Decimal>>();

    if (scope == null || scope.isEmpty()) {
      return pricesByProduct;
    }

    for (PricebookEntry pricebookEntry : [
      SELECT Id, Product2Id, Pricebook2Id, UnitPrice, ProductSellingModelId
      FROM PricebookEntry
      WHERE Product2Id IN :scope AND IsActive = TRUE AND UnitPrice != NULL
    ]) {
      if (pricebookEntry.Product2Id == null) {
        continue;
      }

      if (!pricesByProduct.containsKey(pricebookEntry.Product2Id)) {
        pricesByProduct.put(pricebookEntry.Product2Id, new Map<String, Decimal>());
      }

      String priceKey = (pricebookEntry.Pricebook2Id == stdPricebookId)
        ? ''
        : (pricebookEntry.ProductSellingModelId == null) ? String.valueOf(pricebookEntry.Pricebook2Id) : String.valueOf(pricebookEntry.Pricebook2Id) + ':' + String.valueOf(pricebookEntry.ProductSellingModelId);
      pricesByProduct.get(pricebookEntry.Product2Id).put(
        priceKey,
        pricebookEntry.UnitPrice
      );
    }

    return pricesByProduct;
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
      Map<Id, CatalogBuyerGroupAccessSnapshot> snapshotsByProductId =
        CatalogBuyerGroupAccessResolver.resolveBuyerGroupAccess(
          jobConfig,
          scope,
          builder
        );
      ndjsonPayload =
        CatalogBuyerGroupPayloadDecorator.decorateFullUpdatePayload(
          ndjsonPayload,
          snapshotsByProductId,
          jobConfig.WebStoreId__c
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
      result.orderingId = Long.valueOf(String.valueOf(response.get('orderingId')));
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
