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
  public Datetime runCutoff;

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

    if (!CatalogSyncMode.isFull(jobConfig)) {
      throw new CatalogJobConfigException(
        'ProductCatalogExportBatch requires SyncMode__c = Full.'
      );
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
      WebStoreId__c,
      Locale__c,
      IsActive__c,
      ProductFilter__c,
      AdditionalProductFields__c,
      BuilderType__c,
        CatalogId__c,
        BatchSize__c,
      EnablePayloadLogging__c,
      EnableBuyerGroupAvailability__c,
      BuyerGroupAvailabilityMode__c,
      SyncMode__c,
      BaselineFullConfigDeveloperName__c
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

  @TestVisible
  public static Id getStandardPricebookId() {
    if (Test.isRunningTest()) {
      return Test.getStandardPricebookId();
    }

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
    runCutoff = System.now();
    List<String> fields = CatalogProductExportSupport.getRequiredProductFields(
      jobConfig
    );
    Database.QueryLocator locator = CatalogJobScopeUtil.buildProductQueryLocator(
      jobConfig,
      fields,
      extraFieldNames
    );

    System.debug('ProductCatalogExportBatch.start query locator created');
    return locator;
  }

  global void execute(Database.BatchableContext bc, List<Product2> scope) {
    Map<Id, Map<String, Decimal>> pricesByProduct =
      CatalogProductExportSupport.loadPricesByProduct(scope, stdPricebookId);

    String ndjsonPayload = CatalogProductExportSupport.buildFullUpdatePayload(
      jobConfig,
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

    CatalogProductExportSupport.StreamResult streamResult =
      CatalogProductExportSupport.streamPayload(jobConfig, ndjsonPayload);

    System.debug(
      LoggingLevel.DEBUG,
      'Coveo stream update response: ' + streamResult.responseBody
    );

    // Capture the first orderingId from the first batch execution
    // This will be used in finish() to delete items from previous runs only
    if (streamResult.orderingId != null && firstOrderingId == null) {
      firstOrderingId = streamResult.orderingId;
    }

    CatalogProductExportSupport.enqueuePayloadLogIfEnabled(
      jobConfig,
      scope.size(),
      vr,
      ndjsonPayload
    );
  }

  global void finish(Database.BatchableContext bc) {
    System.debug(
      'ProductCatalogExportBatch.finish: firstOrderingId=' + firstOrderingId
    );

    if (!batchCompletedWithoutErrors(bc)) {
      return;
    }

    // Delete older items for this specific source
    // Use firstOrderingId to preserve all items from the current run
    CoveoDeleteOlderThan.deleteOlderThan(
      jobConfig.CoveoOrgId__c,
      jobConfig.SourceId__c,
      firstOrderingId
    );

    CatalogSyncStateService.recordSuccessfulFullSync(
      jobConfig,
      runCutoff == null ? System.now() : runCutoff
    );

    // Payload logs are inserted asynchronously via CoveoPayloadLogQueueable
    // when EnablePayloadLogging__c is enabled
  }

  @TestVisible
  static Boolean batchCompletedWithoutErrors(Database.BatchableContext bc) {
    if (bc == null) {
      return true;
    }

    List<AsyncApexJob> jobs = [
      SELECT Status, NumberOfErrors
      FROM AsyncApexJob
      WHERE Id = :bc.getJobId()
      LIMIT 1
    ];

    return !jobs.isEmpty() &&
      jobs[0].Status == 'Completed' &&
      jobs[0].NumberOfErrors == 0;
  }

  @TestVisible
  static Set<Id> getProductIdsForCatalog(Id catalogId) {
    Set<Id> productIds = new Set<Id>();

    if (catalogId == null) {
      return productIds;
    }

    for (ProductCategoryProduct pcp : [
      SELECT ProductId
      FROM ProductCategoryProduct
      WHERE ProductCategory.CatalogId = :catalogId AND ProductId != NULL
    ]) {
      productIds.add(pcp.ProductId);
    }

    return productIds;
  }

  @TestVisible
  static String validateAndSanitizeFilter(String filter) {
    if (String.isBlank(filter)) {
      return filter;
    }

    String trimmedFilter = filter.trim();
    String normalizedFilter = trimmedFilter.replaceAll('[\\t\\n\\r]+', ' ')
      .toUpperCase();

    List<String> dmlPatterns = new List<String>{
      'INSERT ',
      'UPDATE ',
      'DELETE ',
      'UPSERT ',
      'MERGE ',
      'UNDELETE '
    };

    for (String pattern : dmlPatterns) {
      if (normalizedFilter.contains(pattern)) {
        throw new CatalogJobException(
          'Invalid ProductFilter__c value: contains DML keyword "' +
            pattern.trim() +
            '". Only valid SOQL WHERE clause fragments are allowed.'
        );
      }
    }

    if (
      normalizedFilter.contains('SELECT ') &&
      normalizedFilter.contains(' FROM ')
    ) {
      throw new CatalogJobException(
        'Invalid ProductFilter__c value: contains subquery pattern. ' +
        'Only simple SOQL WHERE clause fragments are allowed.'
      );
    }

    return trimmedFilter;
  }
}
