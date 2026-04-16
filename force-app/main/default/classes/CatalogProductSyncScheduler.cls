global with sharing class CatalogProductSyncScheduler implements Schedulable {
  @TestVisible private static final String JOB_NAME_PREFIX = 'Catalog Product Sync';
  @TestVisible private static CatalogJobConfig__mdt testJobConfigOverride;
  @TestVisible private static Boolean skipBatchExecutionInTests = false;
  @TestVisible private static String lastExecutedConfigDeveloperName;
  @TestVisible private static String lastExecutedSyncMode;

  private String jobConfigDeveloperName;
  private String expectedSyncMode;

  global CatalogProductSyncScheduler() {}

  public CatalogProductSyncScheduler(
    String jobConfigDeveloperName,
    String expectedSyncMode
  ) {
    this.jobConfigDeveloperName = jobConfigDeveloperName;
    this.expectedSyncMode = CatalogSyncMode.resolve(expectedSyncMode);
  }

  global void execute(SchedulableContext context) {
    if (String.isBlank(jobConfigDeveloperName)) {
      return;
    }

    CatalogJobConfig__mdt config = loadJobConfig(jobConfigDeveloperName);
    String scheduledMode = CatalogSyncMode.resolve(expectedSyncMode);
    String resolvedConfigMode = CatalogSyncMode.resolve(config);

    if (resolvedConfigMode != scheduledMode) {
      throw new CatalogJobConfigException(
        'Scheduled job expected SyncMode__c = ' +
        scheduledMode +
        ' for ' +
        jobConfigDeveloperName +
        ', but the config resolves to ' +
        resolvedConfigMode +
        '.'
      );
    }

    if (Test.isRunningTest() && skipBatchExecutionInTests) {
      lastExecutedConfigDeveloperName = jobConfigDeveloperName;
      lastExecutedSyncMode = scheduledMode;
      return;
    }

    if (scheduledMode == CatalogSyncMode.DELTA) {
      DeltaProductCatalogExportBatch deltaBatch =
        new DeltaProductCatalogExportBatch(jobConfigDeveloperName);
      Database.executeBatch(deltaBatch, deltaBatch.getBatchSize());
      return;
    }

    ProductCatalogExportBatch fullBatch = new ProductCatalogExportBatch(
      jobConfigDeveloperName
    );
    Database.executeBatch(fullBatch, fullBatch.getBatchSize());
  }

  public static String scheduleFullSync(
    String jobConfigDeveloperName,
    String cronExpression
  ) {
    return System.schedule(
      buildScheduledJobName(jobConfigDeveloperName, CatalogSyncMode.FULL),
      cronExpression,
      new CatalogProductSyncScheduler(
        jobConfigDeveloperName,
        CatalogSyncMode.FULL
      )
    );
  }

  public static String scheduleDeltaSync(
    String jobConfigDeveloperName,
    String cronExpression
  ) {
    return System.schedule(
      buildScheduledJobName(jobConfigDeveloperName, CatalogSyncMode.DELTA),
      cronExpression,
      new CatalogProductSyncScheduler(
        jobConfigDeveloperName,
        CatalogSyncMode.DELTA
      )
    );
  }

  @TestVisible
  private static String buildScheduledJobName(
    String jobConfigDeveloperName,
    String syncMode
  ) {
    return JOB_NAME_PREFIX +
      ' [' +
      CatalogSyncMode.resolve(syncMode) +
      '] ' +
      (String.isBlank(jobConfigDeveloperName)
        ? 'Unknown Config'
        : jobConfigDeveloperName.trim());
  }

  @TestVisible
  private static CatalogJobConfig__mdt loadJobConfig(
    String developerName
  ) {
    if (
      Test.isRunningTest() &&
      testJobConfigOverride != null &&
      testJobConfigOverride.DeveloperName == developerName
    ) {
      return testJobConfigOverride;
    }

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
      WHERE DeveloperName = :developerName
      LIMIT 1
    ];

    if (configs.isEmpty()) {
      throw new CatalogJobException(
        'No CatalogJobConfig__mdt record found with DeveloperName: ' +
        developerName
      );
    }

    return configs[0];
  }
}
