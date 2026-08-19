global with sharing class DeltaProductCatalogExportBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
  @TestVisible
  private static CatalogJobConfig__mdt testJobConfigOverride;
  private final CatalogJobConfig__mdt jobConfig;
  private final List<String> extraFieldNames = new List<String>();
  private final Id stdPricebookId;
  private final Set<Id> targetPricebookIds;
  private final Map<Id, String> labelsByPricebookId;

  public Datetime baselineTimestamp;
  public Datetime runCutoff;

  public DeltaProductCatalogExportBatch(String jobConfigDeveloperName) {
    this(
      loadJobConfig(jobConfigDeveloperName),
      ProductCatalogExportBatch.getStandardPricebookId(),
      null,
      null
    );
  }

  public DeltaProductCatalogExportBatch(
    String jobConfigDeveloperName,
    Datetime baselineTimestamp,
    Datetime runCutoff
  ) {
    this(
      loadJobConfig(jobConfigDeveloperName),
      ProductCatalogExportBatch.getStandardPricebookId(),
      baselineTimestamp,
      runCutoff
    );
  }

  @TestVisible
  private DeltaProductCatalogExportBatch(
    CatalogJobConfig__mdt jobConfig,
    Id stdPricebookId,
    Datetime baselineTimestamp
  ) {
    this(jobConfig, stdPricebookId, baselineTimestamp, null);
  }

  @TestVisible
  private DeltaProductCatalogExportBatch(
    CatalogJobConfig__mdt jobConfig,
    Id stdPricebookId,
    Datetime baselineTimestamp,
    Datetime runCutoff
  ) {
    if (jobConfig == null) {
      throw new CatalogJobException('Catalog job config is required.');
    }

    if (!CatalogSyncMode.isDelta(jobConfig)) {
      throw new CatalogJobConfigException(
        'DeltaProductCatalogExportBatch requires SyncMode__c = Delta.'
      );
    }

    this.jobConfig = jobConfig;
    this.stdPricebookId = stdPricebookId;
    WebStorePricebookResolver.PricebookResolution pricebookResolution = WebStorePricebookResolver.resolve(
      jobConfig
    );
    this.targetPricebookIds = pricebookResolution.pricebookIds;
    this.labelsByPricebookId = pricebookResolution.labelsByPricebookId;
    this.baselineTimestamp = baselineTimestamp;
    this.runCutoff = runCutoff;
    extraFieldNames.addAll(
      CatalogProductExportSupport.parseExtraFieldNames(
        jobConfig.AdditionalProductFields__c
      )
    );
  }

  private static CatalogJobConfig__mdt loadJobConfig(
    String jobConfigDeveloperName
  ) {
    if (
      Test.isRunningTest() &&
      testJobConfigOverride != null &&
      testJobConfigOverride.DeveloperName == jobConfigDeveloperName
    ) {
      return testJobConfigOverride;
    }

    List<CatalogJobConfig__mdt> configs = [
      SELECT
        DeveloperName,
        Label,
        CoveoOrgId__c,
        SourceId__c,
        WebStoreId__c,
        WebStoreIds__c,
        PricebookIds__c,
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

  public Integer getBatchSize() {
    if (jobConfig.BatchSize__c != null) {
      return Integer.valueOf(jobConfig.BatchSize__c);
    }
    return 50;
  }

  global Database.QueryLocator start(Database.BatchableContext bc) {
    if (baselineTimestamp == null) {
      CatalogSyncStateService.DeltaReadiness readiness = CatalogSyncStateService.requireDeltaReadiness(
        jobConfig
      );
      baselineTimestamp = readiness.stateRecord.LastSuccessfulSyncAt__c;
    }

    if (runCutoff == null) {
      runCutoff = System.now();
    }

    Set<Id> exportProductIds = CatalogDeltaScopeResolver.resolveExportProductIds(
      jobConfig,
      baselineTimestamp,
      runCutoff
    );

    return CatalogJobScopeUtil.buildProductQueryLocatorForIds(
      jobConfig,
      exportProductIds,
      CatalogProductExportSupport.getRequiredProductFields(jobConfig),
      extraFieldNames
    );
  }

  global void execute(Database.BatchableContext bc, List<Product2> scope) {
    Map<Id, Map<String, Decimal>> pricesByProduct = CatalogProductExportSupport.loadPricesByProduct(
      scope,
      stdPricebookId,
      targetPricebookIds,
      labelsByPricebookId
    );

    String ndjsonPayload = CatalogProductExportSupport.buildFullUpdatePayload(
      jobConfig,
      scope,
      pricesByProduct,
      extraFieldNames
    );

    CoveoPayloadValidator.Result validationResult = CoveoPayloadValidator.validate(
      ndjsonPayload
    );
    CatalogProductExportSupport.streamPayload(jobConfig, ndjsonPayload);
    CatalogProductExportSupport.enqueuePayloadLogIfEnabled(
      jobConfig,
      scope.size(),
      validationResult,
      ndjsonPayload
    );
  }

  global void finish(Database.BatchableContext bc) {
    if (!batchCompletedWithoutErrors(bc)) {
      return;
    }

    CatalogSyncStateService.recordSuccessfulDeltaSync(
      jobConfig,
      runCutoff == null ? System.now() : runCutoff
    );
  }

  @TestVisible
  private static Boolean batchCompletedWithoutErrors(
    Database.BatchableContext bc
  ) {
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
}
