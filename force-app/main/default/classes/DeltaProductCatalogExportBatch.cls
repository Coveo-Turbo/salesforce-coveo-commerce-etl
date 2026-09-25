global with sharing class DeltaProductCatalogExportBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
  @TestVisible
  private static CatalogJobConfig__mdt testJobConfigOverride;
  private CatalogJobConfig__mdt jobConfig;
  private final List<String> extraFieldNames = new List<String>();
  private Id stdPricebookId;
  private Set<Id> targetPricebookIds;
  private Map<Id, String> labelsByPricebookId;
  private Id runId;
  private Boolean bootstrapMode = true;
  private Integer exportedProductCount = 0;

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

  public DeltaProductCatalogExportBatch(
    Id runId,
    CatalogJobConfig__mdt jobConfig
  ) {
    if (runId == null) {
      throw new CatalogJobException('Catalog delta run ID is required.');
    }
    if (jobConfig == null || !CatalogSyncMode.isDelta(jobConfig)) {
      throw new CatalogJobConfigException(
        'DeltaProductCatalogExportBatch requires SyncMode__c = Delta.'
      );
    }

    Catalog_Delta_Run__c run = CatalogDeltaRunService.loadRun(runId);
    CatalogJobConfig__mdt resolvedConfig = hydrateJobConfig(jobConfig);
    this.runId = runId;
    this.jobConfig = resolvedConfig;
    this.bootstrapMode = false;
    this.stdPricebookId = String.isBlank(run.StandardPricebookId__c)
      ? null
      : (Id) run.StandardPricebookId__c;
    this.targetPricebookIds = CatalogDeltaRunService.getResolvedPricebookIds(run);
    this.labelsByPricebookId = CatalogDeltaRunService.getPricebookLabels(run);
    this.baselineTimestamp = run.BaselineTimestamp__c;
    this.runCutoff = run.CutoffTimestamp__c;
    extraFieldNames.addAll(
      CatalogProductExportSupport.parseExtraFieldNames(
        resolvedConfig.AdditionalProductFields__c
      )
    );
  }

  /**
   * Reloads the config through the shared selector so the export stage never
   * depends on the SELECT list used by whichever class launched the run. A
   * partially queried config reaching execute() previously failed the export
   * stage with "SObject row was retrieved via SOQL without querying the
   * requested field". Falls back to the supplied config when no matching
   * custom metadata record exists, which keeps in-memory test configs usable.
   */
  @TestVisible
  private static CatalogJobConfig__mdt hydrateJobConfig(
    CatalogJobConfig__mdt jobConfig
  ) {
    if (jobConfig == null) {
      return null;
    }

    if (
      Test.isRunningTest() &&
      testJobConfigOverride != null &&
      testJobConfigOverride.DeveloperName == jobConfig.DeveloperName
    ) {
      return testJobConfigOverride;
    }

    CatalogJobConfig__mdt reloadedConfig = CatalogJobConfigSelector.findByDeveloperName(
      jobConfig.DeveloperName
    );

    return reloadedConfig == null ? jobConfig : reloadedConfig;
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

    return CatalogJobConfigSelector.requireByDeveloperName(
      jobConfigDeveloperName
    );
  }

  public Integer getBatchSize() {
    if (jobConfig.BatchSize__c != null) {
      return Integer.valueOf(jobConfig.BatchSize__c);
    }
    return 50;
  }

  global Database.QueryLocator start(Database.BatchableContext bc) {
    if (bootstrapMode == true) {
      return Database.getQueryLocator(
        'SELECT Id FROM Product2 WHERE Id = NULL'
      );
    }

    Catalog_Delta_Run__c run = CatalogDeltaRunService.loadRun(runId);
    if (
      run.Status__c != CatalogDeltaRunService.STATUS_RUNNING ||
      run.Stage__c != CatalogDeltaStageBatch.EXPORT_PRODUCTS
    ) {
      return Database.getQueryLocator(
        'SELECT Id FROM Product2 WHERE Id = NULL'
      );
    }

    return CatalogJobScopeUtil.buildProductQueryLocatorForDeltaRun(
      jobConfig,
      runId,
      CatalogProductExportSupport.getRequiredProductFields(jobConfig),
      extraFieldNames
    );
  }

  global void execute(Database.BatchableContext bc, List<Product2> scope) {
    exportedProductCount += scope == null ? 0 : scope.size();
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
      if (bootstrapMode != true && runId != null) {
        CatalogDeltaRunService.failRun(
          runId,
          'Delta product export failed. Review the Async Apex job for details.'
        );
      }
      return;
    }

    if (bootstrapMode == true) {
      if (baselineTimestamp == null) {
        CatalogDeltaRunService.launch(jobConfig);
      } else {
        CatalogDeltaRunService.launch(
          jobConfig,
          baselineTimestamp,
          runCutoff == null ? System.now() : runCutoff
        );
      }
      return;
    }

    CatalogDeltaRunService.completeRun(
      runId,
      jobConfig,
      exportedProductCount
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
      jobs[0].NumberOfErrors == 0 &&
      jobs[0].Status != 'Failed' &&
      jobs[0].Status != 'Aborted';
  }
}
