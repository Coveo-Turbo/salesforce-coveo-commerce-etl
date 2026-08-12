public with sharing class CatalogJobRunner {
  private static final String PRODUCT_BATCH_CLASS = 'ProductCatalogExportBatch';
  private static final String AVAILABILITY_BATCH_CLASS = 'BuyerGroupAvailabilityExportBatch';
  private static final String ACCESS_BATCH_CLASS = 'EmbeddedBuyerGroupAccessExportBatch';

  public class JobLaunchHandle {
    @AuraEnabled
    public String jobId { get; set; }

    @AuraEnabled
    public String channel { get; set; }

    @AuraEnabled
    public String label { get; set; }

    @AuraEnabled
    public Integer impactedProductCount { get; set; }

    @AuraEnabled
    public Integer changedRootProductCount { get; set; }

    @AuraEnabled
    public Integer exportProductCount { get; set; }

    @AuraEnabled
    public String scopeSummary { get; set; }
  }

  public class LaunchResult {
    @AuraEnabled
    public String runKey { get; set; }

    @AuraEnabled
    public String developerName { get; set; }

    @AuraEnabled
    public String label { get; set; }

    @AuraEnabled
    public String mode { get; set; }

    @AuraEnabled
    public String productSyncMode { get; set; }

    @AuraEnabled
    public Boolean availabilityEnabled { get; set; }

    @AuraEnabled
    public String buyerGroupAvailabilityMode { get; set; }

    @AuraEnabled
    public String launchedAt { get; set; }

    @AuraEnabled
    public List<JobLaunchHandle> jobs { get; set; }
  }

  public class RunSnapshot {
    @AuraEnabled
    public String jobId { get; set; }

    @AuraEnabled
    public String channel { get; set; }

    @AuraEnabled
    public String apexClassName { get; set; }

    @AuraEnabled
    public String status { get; set; }

    @AuraEnabled
    public Integer jobItemsProcessed { get; set; }

    @AuraEnabled
    public Integer totalJobItems { get; set; }

    @AuraEnabled
    public Integer numberOfErrors { get; set; }

    @AuraEnabled
    public String extendedStatus { get; set; }

    @AuraEnabled
    public Boolean isTerminal { get; set; }

    @AuraEnabled
    public String createdDate { get; set; }

    @AuraEnabled
    public String completedDate { get; set; }
  }

  @AuraEnabled(cacheable=true)
  public static List<CatalogJobConfig__mdt> listConfigs() {
    return [
      SELECT
        DeveloperName,
        Label,
        CoveoOrgId__c,
        SourceId__c,
        AvailabilitySourceId__c,
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
        EnableBuyerGroupAvailability__c,
        BuyerGroupAvailabilityMode__c,
        SyncMode__c,
        BaselineFullConfigDeveloperName__c
      FROM CatalogJobConfig__mdt
      ORDER BY Label
    ];
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getConsoleConfigs() {
    List<CatalogJobConfig__mdt> configs = listConfigs();
    Map<String, CatalogSyncStateService.Snapshot> snapshotsByDeveloperName = CatalogSyncStateService.getSnapshotsByDeveloperName(
      configs
    );
    Map<String, CatalogProductSyncScheduler.ScheduleSnapshot> scheduleSnapshotsByDeveloperName = CatalogProductSyncScheduler.getScheduleSnapshotsByDeveloperName(
      configs
    );
    List<Map<String, Object>> consoleConfigs = new List<Map<String, Object>>();

    for (CatalogJobConfig__mdt config : configs) {
      CatalogSyncStateService.Snapshot snapshot = snapshotsByDeveloperName.get(
        config.DeveloperName
      );
      CatalogProductSyncScheduler.ScheduleSnapshot scheduleSnapshot = scheduleSnapshotsByDeveloperName.get(
        config.DeveloperName
      );
      consoleConfigs.add(
        new Map<String, Object>{
          'DeveloperName' => config.DeveloperName,
          'Label' => config.Label,
          'CoveoOrgId__c' => config.CoveoOrgId__c,
          'SourceId__c' => config.SourceId__c,
          'AvailabilitySourceId__c' => config.AvailabilitySourceId__c,
          'WebStoreId__c' => config.WebStoreId__c,
          'WebStoreIds__c' => config.WebStoreIds__c,
          'PricebookIds__c' => config.PricebookIds__c,
          'Locale__c' => config.Locale__c,
          'IsActive__c' => config.IsActive__c,
          'ProductFilter__c' => config.ProductFilter__c,
          'AdditionalProductFields__c' => config.AdditionalProductFields__c,
          'BuilderType__c' => config.BuilderType__c,
          'CatalogId__c' => config.CatalogId__c,
          'BatchSize__c' => config.BatchSize__c,
          'EnableBuyerGroupAvailability__c' => config.EnableBuyerGroupAvailability__c,
          'BuyerGroupAvailabilityMode__c' => config.BuyerGroupAvailabilityMode__c,
          'SyncMode__c' => CatalogSyncMode.resolve(config),
          'BaselineFullConfigDeveloperName__c' => config.BaselineFullConfigDeveloperName__c,
          'deltaReady' => snapshot == null ? true : snapshot.deltaReady,
          'deltaReadinessMessage' => snapshot == null
            ? null
            : snapshot.deltaReadinessMessage,
          'lastSuccessfulFullSyncAt' => snapshot == null
            ? null
            : snapshot.lastSuccessfulFullSyncAt,
          'lastSuccessfulSyncAt' => snapshot == null
            ? null
            : snapshot.lastSuccessfulSyncAt,
          'lastRunMode' => snapshot == null ? null : snapshot.lastRunMode,
          'lastSuccessfulConfigDeveloperName' => snapshot == null
            ? null
            : snapshot.lastSuccessfulConfigDeveloperName,
          'currentProductJobId' => snapshot == null
            ? null
            : snapshot.currentProductJobId,
          'currentProductJobStatus' => snapshot == null
            ? null
            : snapshot.currentProductJobStatus,
          'currentProductRunMode' => snapshot == null
            ? null
            : snapshot.currentProductRunMode,
          'currentProductConfigDeveloperName' => snapshot == null
            ? null
            : snapshot.currentProductConfigDeveloperName,
          'currentProductStartedAt' => snapshot == null
            ? null
            : snapshot.currentProductStartedAt,
          'currentProductIsActive' => snapshot == null
            ? false
            : snapshot.currentProductIsActive,
          'recentProductRuns' => snapshot == null
            ? new List<Object>()
            : snapshot.recentProductRuns,
          'isScheduled' => scheduleSnapshot == null
            ? false
            : scheduleSnapshot.isScheduled,
          'scheduleState' => scheduleSnapshot == null
            ? null
            : scheduleSnapshot.state,
          'scheduleCadenceRecognized' => scheduleSnapshot == null
            ? false
            : scheduleSnapshot.cadenceRecognized,
          'scheduleCadenceType' => scheduleSnapshot == null
            ? null
            : scheduleSnapshot.cadenceType,
          'scheduleIntervalMinutes' => scheduleSnapshot == null
            ? null
            : scheduleSnapshot.intervalMinutes,
          'scheduleIntervalHours' => scheduleSnapshot == null
            ? null
            : scheduleSnapshot.intervalHours,
          'scheduleDayOfWeek' => scheduleSnapshot == null
            ? null
            : scheduleSnapshot.dayOfWeek,
          'scheduleHourOfDay' => scheduleSnapshot == null
            ? null
            : scheduleSnapshot.hourOfDay,
          'scheduleMinuteOfHour' => scheduleSnapshot == null
            ? null
            : scheduleSnapshot.minuteOfHour,
          'scheduleNextFireTime' => scheduleSnapshot == null
            ? null
            : (scheduleSnapshot.nextFireTime == null
                ? null
                : scheduleSnapshot.nextFireTime.formatGmt(
                    'yyyy-MM-dd\'T\'HH:mm:ss\'Z\''
                  )),
          'resolvedTargetKey' => snapshot == null
            ? CatalogSyncStateService.buildResolvedTargetKey(config)
            : snapshot.resolvedTargetKey
        }
      );
    }

    return consoleConfigs;
  }

  @AuraEnabled
  public static LaunchResult runSingle(String jobConfigDeveloperName) {
    CatalogJobConfig__mdt config = getConfig(jobConfigDeveloperName);
    validateProductSyncReady(config);
    return launchForConfig(config, true, false, 'products');
  }

  @AuraEnabled
  public static LaunchResult runSingleAvailability(
    String jobConfigDeveloperName
  ) {
    CatalogJobConfig__mdt config = getConfig(jobConfigDeveloperName);
    validateBuyerGroupAccessEnabled(config);
    return launchForConfig(config, false, true, 'availability');
  }

  @AuraEnabled
  public static LaunchResult runSingleBoth(String jobConfigDeveloperName) {
    CatalogJobConfig__mdt config = getConfig(jobConfigDeveloperName);
    validateBuyerGroupAccessEnabled(config);
    validateProductSyncReady(config);
    return launchForConfig(config, true, true, 'both');
  }

  @AuraEnabled
  public static List<LaunchResult> runAllActive() {
    List<LaunchResult> launches = new List<LaunchResult>();
    for (CatalogJobConfig__mdt config : getActiveConfigs()) {
      if (!isProductSyncReady(config)) {
        continue;
      }
      launches.add(launchForConfig(config, true, false, 'products'));
    }
    return launches;
  }

  @AuraEnabled
  public static List<LaunchResult> runAllActiveAvailability() {
    List<LaunchResult> launches = new List<LaunchResult>();
    for (CatalogJobConfig__mdt config : getActiveConfigs()) {
      if (CatalogBuyerGroupAvailabilityMode.isBuyerGroupAccessEnabled(config)) {
        launches.add(launchForConfig(config, false, true, 'availability'));
      }
    }
    return launches;
  }

  @AuraEnabled
  public static List<LaunchResult> runAllActiveBoth() {
    List<LaunchResult> launches = new List<LaunchResult>();
    for (CatalogJobConfig__mdt config : getActiveConfigs()) {
      if (!isProductSyncReady(config)) {
        continue;
      }
      launches.add(
        launchForConfig(
          config,
          true,
          CatalogBuyerGroupAvailabilityMode.isBuyerGroupAccessEnabled(config),
          CatalogBuyerGroupAvailabilityMode.isBuyerGroupAccessEnabled(config)
            ? 'both'
            : 'products'
        )
      );
    }
    return launches;
  }

  public static String runAllActiveChained() {
    List<String> configDeveloperNames = new List<String>();
    for (CatalogJobConfig__mdt config : getActiveConfigs()) {
      if (isProductSyncReady(config)) {
        configDeveloperNames.add(config.DeveloperName);
      }
    }
    return enqueueChain(configDeveloperNames, null, true, false);
  }

  public static String runAllActiveAvailabilityChained() {
    List<String> configDeveloperNames = new List<String>();
    for (CatalogJobConfig__mdt config : getActiveConfigs()) {
      if (CatalogBuyerGroupAvailabilityMode.isBuyerGroupAccessEnabled(config)) {
        configDeveloperNames.add(config.DeveloperName);
      }
    }
    return enqueueChain(configDeveloperNames, null, false, true);
  }

  public static String runAllActiveChained(
    String syncMode,
    Boolean includeAvailability
  ) {
    String resolvedSyncMode = String.isBlank(syncMode)
      ? null
      : CatalogSyncMode.resolve(syncMode);
    List<String> configDeveloperNames = new List<String>();
    for (CatalogJobConfig__mdt config : getActiveConfigs()) {
      if (
        (resolvedSyncMode == null ||
        CatalogSyncMode.resolve(config) == resolvedSyncMode) &&
        isProductSyncReady(config)
      ) {
        configDeveloperNames.add(config.DeveloperName);
      }
    }
    return enqueueChain(
      configDeveloperNames,
      resolvedSyncMode,
      true,
      includeAvailability
    );
  }

  public static LaunchResult runChainedConfig(
    String jobConfigDeveloperName,
    String expectedSyncMode,
    Boolean runProducts,
    Boolean includeAvailability
  ) {
    CatalogJobConfig__mdt config = getConfig(jobConfigDeveloperName);
    if (config.IsActive__c != true) {
      return null;
    }

    String resolvedConfigMode = CatalogSyncMode.resolve(config);
    if (
      String.isNotBlank(expectedSyncMode) &&
      resolvedConfigMode != CatalogSyncMode.resolve(expectedSyncMode)
    ) {
      throw new CatalogJobConfigException(
        'Chained sync expected SyncMode__c = ' +
          CatalogSyncMode.resolve(expectedSyncMode) +
          ' for ' +
          jobConfigDeveloperName +
          ', but the config resolves to ' +
          resolvedConfigMode +
          '.'
      );
    }

    Boolean shouldRunProducts =
      runProducts == true && isProductSyncReady(config);
    Boolean shouldRunAvailability =
      includeAvailability == true &&
      CatalogBuyerGroupAvailabilityMode.isBuyerGroupAccessEnabled(config);
    if (!shouldRunProducts && !shouldRunAvailability) {
      return null;
    }

    return launchForConfig(
      config,
      shouldRunProducts,
      shouldRunAvailability,
      shouldRunProducts && shouldRunAvailability
        ? 'both'
        : shouldRunProducts ? 'products' : 'availability'
    );
  }

  private static String enqueueChain(
    List<String> configDeveloperNames,
    String syncMode,
    Boolean runProducts,
    Boolean includeAvailability
  ) {
    if (configDeveloperNames == null || configDeveloperNames.isEmpty()) {
      return null;
    }
    return String.valueOf(
      System.enqueueJob(
        new CatalogSyncChainQueueable(
          configDeveloperNames,
          syncMode,
          runProducts,
          includeAvailability
        )
      )
    );
  }

  @AuraEnabled
  public static String abortCurrentProductRun(String jobConfigDeveloperName) {
    CatalogJobConfig__mdt config = getConfig(jobConfigDeveloperName);
    CatalogSyncStateService.Snapshot snapshot = CatalogSyncStateService.getSnapshotsByDeveloperName(
        new List<CatalogJobConfig__mdt>{ config }
      )
      .get(config.DeveloperName);

    if (
      snapshot == null ||
      snapshot.currentProductIsActive != true ||
      String.isBlank(snapshot.currentProductJobId)
    ) {
      throw new CatalogJobConfigException(
        'No active product sync is currently tracked for ' + config.Label + '.'
      );
    }

    abortAsyncJob(snapshot.currentProductJobId);
    return snapshot.currentProductJobId;
  }

  @AuraEnabled
  public static String abortRunJob(String jobId) {
    if (String.isBlank(jobId)) {
      throw new CatalogJobConfigException('A job id is required.');
    }

    List<RunSnapshot> snapshots = getRunSnapshots(
      new List<String>{ jobId.trim() }
    );
    if (snapshots.isEmpty()) {
      throw new CatalogJobConfigException(
        'No async Apex job was found for id ' + jobId.trim() + '.'
      );
    }

    abortAsyncJob(jobId.trim());
    return jobId.trim();
  }

  @AuraEnabled
  public static List<RunSnapshot> getRunSnapshots(List<String> jobIds) {
    if (jobIds == null || jobIds.isEmpty()) {
      return new List<RunSnapshot>();
    }

    Set<Id> validIds = new Set<Id>();
    for (String jobId : jobIds) {
      if (String.isBlank(jobId)) {
        continue;
      }

      try {
        validIds.add((Id) jobId);
      } catch (Exception e) {
        // Ignore invalid ids so the caller can keep polling the rest.
      }
    }

    if (validIds.isEmpty()) {
      return new List<RunSnapshot>();
    }

    Map<Id, AsyncApexJob> jobsById = new Map<Id, AsyncApexJob>(
      [
        SELECT
          Id,
          Status,
          JobItemsProcessed,
          TotalJobItems,
          NumberOfErrors,
          ExtendedStatus,
          CreatedDate,
          CompletedDate,
          ApexClass.Name
        FROM AsyncApexJob
        WHERE Id IN :validIds
      ]
    );

    List<RunSnapshot> snapshots = new List<RunSnapshot>();
    for (String requestedId : jobIds) {
      if (String.isBlank(requestedId)) {
        continue;
      }

      AsyncApexJob job;
      try {
        job = jobsById.get((Id) requestedId);
      } catch (Exception e) {
        job = null;
      }

      if (job == null) {
        continue;
      }

      RunSnapshot snapshot = new RunSnapshot();
      snapshot.jobId = String.valueOf(job.Id);
      snapshot.apexClassName = job.ApexClass != null
        ? job.ApexClass.Name
        : null;
      snapshot.channel = inferChannel(snapshot.apexClassName);
      snapshot.status = job.Status;
      snapshot.jobItemsProcessed = job.JobItemsProcessed;
      snapshot.totalJobItems = job.TotalJobItems;
      snapshot.numberOfErrors = job.NumberOfErrors;
      snapshot.extendedStatus = job.ExtendedStatus;
      snapshot.isTerminal = isTerminalStatus(job.Status);
      snapshot.createdDate = job.CreatedDate == null
        ? null
        : job.CreatedDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
      snapshot.completedDate = job.CompletedDate == null
        ? null
        : job.CompletedDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
      snapshots.add(snapshot);
    }

    return snapshots;
  }

  @TestVisible
  private static void abortAsyncJob(String jobId) {
    List<RunSnapshot> snapshots = getRunSnapshots(new List<String>{ jobId });
    if (snapshots.isEmpty()) {
      return;
    }

    if (snapshots[0].isTerminal == true) {
      return;
    }

    System.abortJob((Id) jobId);
  }

  private static LaunchResult launchForConfig(
    CatalogJobConfig__mdt config,
    Boolean runProducts,
    Boolean runAvailability,
    String mode
  ) {
    LaunchResult launch = createLaunchResult(config, mode);
    JobLaunchHandle productLaunch = runProducts == true
      ? launchProductJob(config)
      : null;
    List<JobLaunchHandle> buyerGroupLaunches = runAvailability == true
      ? launchBuyerGroupJobs(config)
      : new List<JobLaunchHandle>();
    appendLaunchHandles(
      launch,
      runProducts,
      productLaunch,
      runAvailability,
      buyerGroupLaunches
    );
    return launch;
  }

  @TestVisible
  private static LaunchResult createLaunchResult(
    CatalogJobConfig__mdt config,
    String mode
  ) {
    LaunchResult launch = new LaunchResult();
    launch.runKey =
      config.DeveloperName +
      '-' +
      mode +
      '-' +
      String.valueOf(DateTime.now().getTime());
    launch.developerName = config.DeveloperName;
    launch.label = config.Label;
    launch.mode = mode;
    launch.productSyncMode = CatalogSyncMode.resolve(config);
    launch.availabilityEnabled = CatalogBuyerGroupAvailabilityMode.isBuyerGroupAccessEnabled(
      config
    );
    launch.buyerGroupAvailabilityMode = CatalogBuyerGroupAvailabilityMode.resolve(
      config
    );
    launch.launchedAt = DateTime.now()
      .formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    launch.jobs = new List<JobLaunchHandle>();
    return launch;
  }

  @TestVisible
  private static void appendLaunchHandles(
    LaunchResult launch,
    Boolean runProducts,
    JobLaunchHandle productLaunch,
    Boolean runAvailability,
    List<JobLaunchHandle> buyerGroupLaunches
  ) {
    if (runProducts == true && productLaunch != null) {
      launch.jobs.add(productLaunch);
    }

    if (runAvailability == true && buyerGroupLaunches != null) {
      launch.jobs.addAll(buyerGroupLaunches);
    }
  }

  private static JobLaunchHandle launchProductJob(
    CatalogJobConfig__mdt config
  ) {
    if (CatalogSyncMode.isDelta(config)) {
      CatalogSyncStateService.DeltaReadiness readiness = CatalogSyncStateService.requireDeltaReadiness(
        config
      );
      Datetime baselineTimestamp = readiness.stateRecord.LastSuccessfulSyncAt__c;
      Datetime runCutoff = System.now();
      CatalogDeltaScopeResolver.ScopeMetrics metrics = CatalogDeltaScopeResolver.describeScope(
        config,
        baselineTimestamp,
        runCutoff
      );
      DeltaProductCatalogExportBatch deltaBatch = new DeltaProductCatalogExportBatch(
        config.DeveloperName,
        baselineTimestamp,
        runCutoff
      );
      Id deltaJobId = Database.executeBatch(
        deltaBatch,
        deltaBatch.getBatchSize()
      );
      CatalogSyncStateService.recordStartedProductSync(
        config,
        CatalogSyncMode.DELTA,
        deltaJobId,
        runCutoff
      );
      return createLaunchHandle(
        deltaJobId,
        'products',
        'Delta Product Sync',
        metrics
      );
    }

    ProductCatalogExportBatch fullBatch = new ProductCatalogExportBatch(
      config.DeveloperName
    );
    Id fullJobId = Database.executeBatch(fullBatch, fullBatch.getBatchSize());
    CatalogSyncStateService.recordStartedProductSync(
      config,
      CatalogSyncMode.FULL,
      fullJobId,
      System.now()
    );
    return createLaunchHandle(fullJobId, 'products', 'Full Product Sync');
  }

  private static JobLaunchHandle launchAvailabilityJob(String developerName) {
    BuyerGroupAvailabilityExportBatch batch = new BuyerGroupAvailabilityExportBatch(
      developerName
    );
    Id jobId = Database.executeBatch(batch, batch.getBatchSize());
    return createLaunchHandle(jobId, 'availability', 'Availability Sync');
  }

  private static JobLaunchHandle launchEmbeddedAccessJob(String developerName) {
    EmbeddedBuyerGroupAccessExportBatch batch = new EmbeddedBuyerGroupAccessExportBatch(
      developerName
    );
    Id jobId = Database.executeBatch(batch, batch.getBatchSize());
    return createLaunchHandle(jobId, 'access', 'Embedded Access Sync');
  }

  private static List<JobLaunchHandle> launchBuyerGroupJobs(
    CatalogJobConfig__mdt config
  ) {
    List<JobLaunchHandle> launchHandles = new List<JobLaunchHandle>();

    if (CatalogBuyerGroupAvailabilityMode.usesPairedSource(config)) {
      launchHandles.add(launchAvailabilityJob(config.DeveloperName));
    }
    if (CatalogBuyerGroupAvailabilityMode.usesEmbedded(config)) {
      launchHandles.add(launchEmbeddedAccessJob(config.DeveloperName));
    }

    return launchHandles;
  }

  @TestVisible
  private static JobLaunchHandle createLaunchHandle(
    Id jobId,
    String channel,
    String label
  ) {
    return createLaunchHandle(jobId, channel, label, null);
  }

  @TestVisible
  private static JobLaunchHandle createLaunchHandle(
    Id jobId,
    String channel,
    String label,
    CatalogDeltaScopeResolver.ScopeMetrics metrics
  ) {
    JobLaunchHandle handle = new JobLaunchHandle();
    handle.jobId = String.valueOf(jobId);
    handle.channel = channel;
    handle.label = label;
    if (metrics != null) {
      handle.impactedProductCount = metrics.impactedProductCount;
      handle.changedRootProductCount = metrics.rootProductCount;
      handle.exportProductCount = metrics.exportProductCount;
      handle.scopeSummary = metrics.exportProductCount > 0
        ? metrics.impactedProductCount +
          ' impacted product' +
          (metrics.impactedProductCount == 1 ? '' : 's') +
          ' since last sync • ' +
          metrics.rootProductCount +
          ' changed root' +
          (metrics.rootProductCount == 1 ? '' : 's') +
          ' • ' +
          metrics.exportProductCount +
          ' product' +
          (metrics.exportProductCount == 1 ? '' : 's') +
          ' queued for export'
        : metrics.impactedProductCount > 0
            ? metrics.impactedProductCount +
              ' impacted product' +
              (metrics.impactedProductCount == 1 ? '' : 's') +
              ' since last sync, but none matched this export scope'
            : 'No changed products since last sync';
    }
    return handle;
  }

  private static CatalogJobConfig__mdt getConfig(
    String jobConfigDeveloperName
  ) {
    List<CatalogJobConfig__mdt> configs = [
      SELECT
        DeveloperName,
        Label,
        CoveoOrgId__c,
        SourceId__c,
        AvailabilitySourceId__c,
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
        SyncMode__c,
        BaselineFullConfigDeveloperName__c,
        EnableBuyerGroupAvailability__c,
        BuyerGroupAvailabilityMode__c
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

  private static List<CatalogJobConfig__mdt> getActiveConfigs() {
    return [
      SELECT
        DeveloperName,
        Label,
        CoveoOrgId__c,
        SourceId__c,
        AvailabilitySourceId__c,
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
        SyncMode__c,
        BaselineFullConfigDeveloperName__c,
        EnableBuyerGroupAvailability__c,
        BuyerGroupAvailabilityMode__c
      FROM CatalogJobConfig__mdt
      WHERE IsActive__c = TRUE
      ORDER BY Label
    ];
  }

  @TestVisible
  private static void validateBuyerGroupAccessEnabled(
    CatalogJobConfig__mdt config
  ) {
    if (!CatalogBuyerGroupAvailabilityMode.isBuyerGroupAccessEnabled(config)) {
      throw new CatalogJobConfigException(
        'Buyer Group access is disabled for ' + config.Label + '.'
      );
    }
  }

  @TestVisible
  private static void validateProductSyncReady(CatalogJobConfig__mdt config) {
    if (CatalogSyncMode.isDelta(config)) {
      CatalogSyncStateService.requireDeltaReadiness(config);
    }
  }

  @TestVisible
  private static Boolean isProductSyncReady(CatalogJobConfig__mdt config) {
    if (!CatalogSyncMode.isDelta(config)) {
      return true;
    }

    try {
      CatalogSyncStateService.requireDeltaReadiness(config);
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  @TestVisible
  private static String inferChannel(String apexClassName) {
    if (apexClassName == AVAILABILITY_BATCH_CLASS) {
      return 'availability';
    }
    if (apexClassName == ACCESS_BATCH_CLASS) {
      return 'access';
    }
    return 'products';
  }

  @TestVisible
  private static Boolean isTerminalStatus(String status) {
    return status == 'Completed' || status == 'Failed' || status == 'Aborted';
  }
}
