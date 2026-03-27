/**
 * Batch job that exports Product2 records to Coveo catalog source.
 *
 * SECURITY NOTE: The ProductFilter__c field in CatalogJobConfig__mdt is used to build
 * dynamic SOQL queries. This field should only contain valid SOQL WHERE clause fragments
 * (e.g., "Family = 'Electronics'" or "ProductCode LIKE 'SKU-%'").
 *
 * Since CatalogJobConfig__mdt is Custom Metadata, only users with the appropriate
 * permissions (typically admins/developers) can modify it. However, administrators
 * should ensure that ProductFilter__c values:
 * - Contain only valid SOQL field references and operators
 * - Do not include DML operations or subqueries that could cause security issues
 * - Are tested before deployment to production
 */
global with sharing class ProductCatalogExportBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
  private final CatalogJobConfig__mdt jobConfig;
  private final List<String> extraFieldNames = new List<String>();
  private final Id stdPricebookId;

  // Track the first orderingId from the initial batch to use in deleteOlderThan
  // Using Database.Stateful only for this field to preserve ordering across batches
  public Long firstOrderingId;

  public ProductCatalogExportBatch(String jobConfigDeveloperName) {
    this(loadJobConfig(jobConfigDeveloperName), getStandardPricebookId());
  }

  @TestVisible
  private ProductCatalogExportBatch(
    CatalogJobConfig__mdt jobConfig,
    Id stdPricebookId
  ) {
    if (jobConfig == null) {
      throw new CatalogJobException('Catalog job config is required.');
    }

    this.jobConfig = jobConfig;
    this.stdPricebookId = stdPricebookId;
    populateExtraFieldNames(jobConfig.AdditionalProductFields__c);
  }

  private static CatalogJobConfig__mdt loadJobConfig(
    String jobConfigDeveloperName
  ) {
    List<CatalogJobConfig__mdt> configs = [
      SELECT
        DeveloperName,
        Label,
        CoveoOrgId__c,
        SourceId__c,
        Locale__c,
        IsActive__c,
        ProductFilter__c,
        AdditionalProductFields__c,
        BuilderType__c,
        CatalogId__c,
        BatchSize__c,
        EnablePayloadLogging__c
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
    return configs[0];
  }

  private static Id getStandardPricebookId() {
    return [
      SELECT Id
      FROM Pricebook2
      WHERE IsStandard = TRUE
      LIMIT 1
    ]
    .Id;
  }

  private void populateExtraFieldNames(String additionalProductFields) {
    if (!String.isBlank(additionalProductFields)) {
      for (String f : additionalProductFields.split(',')) {
        String trimmed = f.trim();
        if (String.isNotBlank(trimmed) && !extraFieldNames.contains(trimmed)) {
          extraFieldNames.add(trimmed);
        }
      }
    }
  }

  /**
   * Returns the configured batch size for this job, defaulting to 50 if not specified.
   * This allows CatalogJobRunner to retrieve the batch size without re-querying the config.
   */
  public Integer getBatchSize() {
    if (jobConfig.BatchSize__c != null) {
      return Integer.valueOf(jobConfig.BatchSize__c);
    }
    return 50; // Default batch size
  }

  global Database.QueryLocator start(Database.BatchableContext bc) {
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
    Database.QueryLocator locator = CatalogJobScopeUtil.buildProductQueryLocator(
      jobConfig,
      fields,
      extraFieldNames
    );

    System.debug('ProductCatalogExportBatch.start query locator created');
    return locator;
  }

  global void execute(Database.BatchableContext bc, List<Product2> scope) {
    // Query all active pricebook entries for products in scope
    // Note: Only active entries with prices are included to optimize query volume
    Map<Id, Map<String, Decimal>> pricesByProduct = new Map<Id, Map<String, Decimal>>();

    for (PricebookEntry pbe : [
      SELECT Id, Product2Id, Pricebook2Id, UnitPrice
      FROM PricebookEntry
      WHERE Product2Id IN :scope AND IsActive = TRUE AND UnitPrice != NULL
    ]) {
      if (pbe.Product2Id == null) {
        continue;
      }

      if (!pricesByProduct.containsKey(pbe.Product2Id)) {
        pricesByProduct.put(pbe.Product2Id, new Map<String, Decimal>());
      }

      // Use empty string for standard pricebook, PricebookId string for others
      String key = (pbe.Pricebook2Id == stdPricebookId)
        ? ''
        : String.valueOf(pbe.Pricebook2Id);
      pricesByProduct.get(pbe.Product2Id).put(key, pbe.UnitPrice);
    }

    ICatalogJsonBuilder builder = CatalogJsonBuilderFactory.getForBuilderType(
      jobConfig.BuilderType__c
    );
    String ndjsonPayload = builder.buildFullUpdateNdjson(
      scope,
      pricesByProduct,
      extraFieldNames
    );

    System.debug(
      LoggingLevel.INFO,
      'CatalogExport NDJSON payload: ' + ndjsonPayload
    );

    // Validate locally
    CoveoPayloadValidator.Result vr = CoveoPayloadValidator.validate(
      ndjsonPayload
    );
    System.debug('Coveo payload validation: ' + JSON.serialize(vr));

    Blob ndjson = Blob.valueOf(ndjsonPayload);

    CoveoStreamClient client = new CoveoStreamClient(
      jobConfig.CoveoOrgId__c,
      jobConfig.SourceId__c
    );
    Map<String, Object> container = client.createFileContainer();
    System.debug(
      LoggingLevel.DEBUG,
      'Coveo file container response: ' + JSON.serialize(container)
    );
    client.uploadNdjson(
      (String) container.get('uploadUri'),
      (Map<String, Object>) container.get('requiredHeaders'),
      ndjson
    );

    String updateResponse = client.streamUpdate(
      (String) container.get('fileId')
    );

    System.debug(
      LoggingLevel.DEBUG,
      'Coveo stream update response: ' + updateResponse
    );

    // Parse orderingId from response body
    Map<String, Object> resMap = (Map<String, Object>) JSON.deserializeUntyped(
      updateResponse
    );

    // Capture the first orderingId from the first batch execution
    // This will be used in finish() to delete items from previous runs only
    if (resMap.containsKey('orderingId') && resMap.get('orderingId') != null) {
      Long oid = Long.valueOf(String.valueOf(resMap.get('orderingId')));
      if (firstOrderingId == null) {
        firstOrderingId = oid;
      }
    }

    // Enqueue payload log AFTER callout to respect Salesforce governor limits
    // Callout → DML ordering is required
    if (jobConfig.EnablePayloadLogging__c == true) {
      Coveo_Payload_Log__c log = new Coveo_Payload_Log__c(
        ScopeSize__c = scope.size(),
        OperationCount__c = vr.operationCount,
        IsValid__c = vr.isValid,
        Reason__c = vr.reason,
        Payload__c = ndjsonPayload.left(32000) // guard against LT max
      );

      // Enqueue queueable job to insert log asynchronously
      // This runs in a separate transaction, avoiding mixed DML
      System.enqueueJob(
        new CoveoPayloadLogQueueable(new List<Coveo_Payload_Log__c>{ log })
      );
    }
  }

  global void finish(Database.BatchableContext bc) {
    System.debug(
      'ProductCatalogExportBatch.finish: firstOrderingId=' + firstOrderingId
    );

    // Delete older items for this specific source
    // Use firstOrderingId to preserve all items from the current run
    CoveoDeleteOlderThan.deleteOlderThan(
      jobConfig.CoveoOrgId__c,
      jobConfig.SourceId__c,
      firstOrderingId
    );

    // Payload logs are inserted asynchronously via CoveoPayloadLogQueueable
    // when EnablePayloadLogging__c is enabled
  }
}
