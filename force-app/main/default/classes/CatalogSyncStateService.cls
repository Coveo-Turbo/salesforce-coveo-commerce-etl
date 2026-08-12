public with sharing class CatalogSyncStateService {
  private static final Integer MAX_RECENT_PRODUCT_RUNS = 8;

  @TestVisible
  private static Map<String, CatalogJobConfig__mdt> testConfigsByDeveloperName;
  @TestVisible
  private static Map<String, Catalog_Sync_State__c> testStatesByTargetKey;
  @TestVisible
  private static Map<String, String> testAsyncJobStatusesById;
  @TestVisible
  private static Map<String, Datetime> testAsyncJobCreatedDatesById;
  @TestVisible
  private static Map<String, Datetime> testAsyncJobCompletedDatesById;

  public class Snapshot {
    public String resolvedTargetKey { get; set; }
    public String syncMode { get; set; }
    public String baselineFullConfigDeveloperName { get; set; }
    public String lastSuccessfulFullSyncAt { get; set; }
    public String lastSuccessfulSyncAt { get; set; }
    public String lastRunMode { get; set; }
    public String lastSuccessfulConfigDeveloperName { get; set; }
    public String currentProductJobId { get; set; }
    public String currentProductJobStatus { get; set; }
    public String currentProductRunMode { get; set; }
    public String currentProductConfigDeveloperName { get; set; }
    public String currentProductStartedAt { get; set; }
    public Boolean currentProductIsActive { get; set; }
    public List<RecentProductRun> recentProductRuns { get; set; }
    public Boolean deltaReady { get; set; }
    public String deltaReadinessMessage { get; set; }
  }

  public class RecentProductRun {
    @AuraEnabled
    public String jobId { get; set; }
    @AuraEnabled
    public String runMode { get; set; }
    @AuraEnabled
    public String configDeveloperName { get; set; }
    @AuraEnabled
    public String status { get; set; }
    @AuraEnabled
    public String startedAt { get; set; }
    @AuraEnabled
    public String completedAt { get; set; }
    @AuraEnabled
    public Boolean isTerminal { get; set; }
  }

  public class DeltaReadiness {
    public CatalogJobConfig__mdt baselineConfig { get; set; }
    public Catalog_Sync_State__c stateRecord { get; set; }
    public String resolvedTargetKey { get; set; }
    public Boolean isReady { get; set; }
    public String message { get; set; }
  }

  private class TrackedAsyncJob {
    public String jobId { get; set; }
    public String status { get; set; }
    public Datetime createdDate { get; set; }
    public Datetime completedDate { get; set; }
    public Boolean isTerminal { get; set; }
  }

  private class StoredRecentProductRun {
    public String jobId { get; set; }
    public String runMode { get; set; }
    public String configDeveloperName { get; set; }
    public String status { get; set; }
    public String startedAt { get; set; }
    public String completedAt { get; set; }
  }

  public static String buildResolvedTargetKey(CatalogJobConfig__mdt jobConfig) {
    List<String> resolvedTarget = new List<String>{
      'orgId',
      normalizeText(jobConfig == null ? null : jobConfig.CoveoOrgId__c),
      'sourceId',
      normalizeText(jobConfig == null ? null : jobConfig.SourceId__c),
      'builderClassName',
      CatalogJsonBuilderFactory.resolveBuilderClassName(
        jobConfig == null ? null : jobConfig.BuilderType__c
      ),
      'catalogId',
      normalizeText(jobConfig == null ? null : jobConfig.CatalogId__c),
      'productFilter',
      normalizeText(jobConfig == null ? null : jobConfig.ProductFilter__c),
      'additionalProductFields',
      canonicalizeCsv(
        jobConfig == null ? null : jobConfig.AdditionalProductFields__c
      ),
      'locale',
      normalizeText(jobConfig == null ? null : jobConfig.Locale__c),
      'pricebookIds',
      canonicalizeIdCsv(
        jobConfig == null ? null : jobConfig.PricebookIds__c,
        'PricebookIds__c'
      ),
      'webStoreIds',
      canonicalizeIdCsv(
        jobConfig == null ? null : jobConfig.WebStoreIds__c,
        'WebStoreIds__c'
      ),
      'buyerGroupAvailabilityMode',
      CatalogBuyerGroupAvailabilityMode.resolve(jobConfig),
      'embeddedWebStoreId',
      (jobConfig != null &&
        CatalogBuyerGroupAvailabilityMode.usesEmbedded(jobConfig))
        ? normalizeText(jobConfig.WebStoreId__c)
        : ''
    };

    return EncodingUtil.convertToHex(
      Crypto.generateDigest(
        'SHA-256',
        Blob.valueOf(JSON.serialize(resolvedTarget))
      )
    );
  }

  public static Map<String, Snapshot> getSnapshotsByDeveloperName(
    List<CatalogJobConfig__mdt> configs
  ) {
    Map<String, Snapshot> snapshotsByDeveloperName = new Map<String, Snapshot>();

    if (configs == null || configs.isEmpty()) {
      return snapshotsByDeveloperName;
    }

    Set<String> deltaBaselineNames = new Set<String>();
    Map<String, String> targetKeyByDeveloperName = new Map<String, String>();

    for (CatalogJobConfig__mdt config : configs) {
      if (String.isBlank(config.DeveloperName)) {
        continue;
      }

      targetKeyByDeveloperName.put(
        config.DeveloperName,
        buildResolvedTargetKey(config)
      );

      if (
        CatalogSyncMode.isDelta(config) &&
        String.isNotBlank(config.BaselineFullConfigDeveloperName__c)
      ) {
        deltaBaselineNames.add(
          config.BaselineFullConfigDeveloperName__c.trim()
        );
      }
    }

    Map<String, CatalogJobConfig__mdt> baselineConfigsByDeveloperName = loadConfigsByDeveloperName(
      deltaBaselineNames
    );
    Set<String> stateKeys = new Set<String>();
    stateKeys.addAll(targetKeyByDeveloperName.values());

    Map<String, String> baselineKeyByDeveloperName = new Map<String, String>();
    for (
      CatalogJobConfig__mdt baselineConfig : baselineConfigsByDeveloperName.values()
    ) {
      String baselineTargetKey = buildResolvedTargetKey(baselineConfig);
      baselineKeyByDeveloperName.put(
        baselineConfig.DeveloperName,
        baselineTargetKey
      );
      stateKeys.add(baselineTargetKey);
    }

    Map<String, Catalog_Sync_State__c> statesByTargetKey = loadStatesByTargetKey(
      stateKeys
    );
    Set<String> trackedProductJobIds = new Set<String>();
    for (Catalog_Sync_State__c stateRecord : statesByTargetKey.values()) {
      if (String.isNotBlank(stateRecord.CurrentProductJobId__c)) {
        trackedProductJobIds.add(stateRecord.CurrentProductJobId__c);
      }

      for (
        StoredRecentProductRun storedRun : extractStoredRecentProductRuns(
          stateRecord
        )
      ) {
        if (String.isNotBlank(storedRun.jobId)) {
          trackedProductJobIds.add(storedRun.jobId);
        }
      }
    }
    Map<String, TrackedAsyncJob> trackedJobsById = loadTrackedJobsById(
      trackedProductJobIds
    );

    for (CatalogJobConfig__mdt config : configs) {
      if (String.isBlank(config.DeveloperName)) {
        continue;
      }

      String targetKey = targetKeyByDeveloperName.get(config.DeveloperName);
      Catalog_Sync_State__c stateRecord = statesByTargetKey.get(targetKey);
      CatalogJobConfig__mdt baselineConfig = String.isBlank(
          config.BaselineFullConfigDeveloperName__c
        )
        ? null
        : baselineConfigsByDeveloperName.get(
            config.BaselineFullConfigDeveloperName__c.trim()
          );
      Snapshot snapshot = buildSnapshot(
        config,
        baselineConfig,
        targetKey,
        baselineConfig == null
          ? null
          : baselineKeyByDeveloperName.get(baselineConfig.DeveloperName),
        stateRecord,
        trackedJobsById.get(
          stateRecord == null ? null : stateRecord.CurrentProductJobId__c
        ),
        trackedJobsById
      );
      snapshotsByDeveloperName.put(config.DeveloperName, snapshot);
    }

    return snapshotsByDeveloperName;
  }

  public static DeltaReadiness requireDeltaReadiness(
    CatalogJobConfig__mdt config
  ) {
    DeltaReadiness readiness = evaluateDeltaReadiness(config);
    if (readiness.isReady != true) {
      throw new CatalogJobConfigException(readiness.message);
    }
    return readiness;
  }

  public static DeltaReadiness evaluateDeltaReadiness(
    CatalogJobConfig__mdt config
  ) {
    DeltaReadiness readiness = new DeltaReadiness();
    readiness.resolvedTargetKey = buildResolvedTargetKey(config);
    readiness.isReady = false;
    readiness.message = 'Delta sync state is unavailable.';

    if (!CatalogSyncMode.isDelta(config)) {
      readiness.isReady = true;
      readiness.message = 'Full sync configuration is ready.';
      return readiness;
    }

    if (String.isBlank(config.BaselineFullConfigDeveloperName__c)) {
      readiness.message = 'BaselineFullConfigDeveloperName__c is required for Delta sync mode.';
      return readiness;
    }

    Map<String, CatalogJobConfig__mdt> configsByDeveloperName = loadConfigsByDeveloperName(
      new Set<String>{ config.BaselineFullConfigDeveloperName__c.trim() }
    );
    readiness.baselineConfig = configsByDeveloperName.get(
      config.BaselineFullConfigDeveloperName__c.trim()
    );

    if (readiness.baselineConfig == null) {
      readiness.message =
        'Baseline full config "' +
        config.BaselineFullConfigDeveloperName__c.trim() +
        '" was not found.';
      return readiness;
    }

    if (!CatalogSyncMode.isFull(readiness.baselineConfig)) {
      readiness.message =
        'Baseline full config "' +
        readiness.baselineConfig.DeveloperName +
        '" must use SyncMode__c = Full.';
      return readiness;
    }

    String baselineTargetKey = buildResolvedTargetKey(readiness.baselineConfig);
    readiness.stateRecord = loadStateByTargetKey(readiness.resolvedTargetKey);
    TrackedAsyncJob trackedJob = loadTrackedJobsById(
        new Set<String>{
          readiness.stateRecord == null
            ? null
            : readiness.stateRecord.CurrentProductJobId__c
        }
      )
      .get(
        readiness.stateRecord == null
          ? null
          : readiness.stateRecord.CurrentProductJobId__c
      );
    String readinessFailure = evaluateDeltaReadinessFailure(
      config,
      readiness.baselineConfig,
      readiness.resolvedTargetKey,
      baselineTargetKey,
      readiness.stateRecord,
      trackedJob
    );
    if (String.isNotBlank(readinessFailure)) {
      readiness.message = readinessFailure;
      return readiness;
    }

    readiness.isReady = true;
    readiness.message = 'Delta sync is ready.';
    return readiness;
  }

  public static void recordSuccessfulFullSync(
    CatalogJobConfig__mdt config,
    Datetime cutoff
  ) {
    String targetKey = buildResolvedTargetKey(config);
    Catalog_Sync_State__c stateRecord = loadStateByTargetKey(targetKey);
    if (stateRecord == null) {
      stateRecord = new Catalog_Sync_State__c();
    }

    stateRecord.ResolvedTargetKey__c = targetKey;
    stateRecord.BaselineFullConfigDeveloperName__c = config.DeveloperName;
    stateRecord.LastSuccessfulFullSyncAt__c = cutoff;
    stateRecord.LastSuccessfulSyncAt__c = cutoff;
    stateRecord.LastRunMode__c = CatalogSyncMode.FULL;
    stateRecord.LastSuccessfulConfigDeveloperName__c = config.DeveloperName;
    markCurrentRecentProductRunCompleted(
      stateRecord,
      CatalogSyncMode.FULL,
      config.DeveloperName,
      cutoff
    );
    upsert stateRecord ResolvedTargetKey__c;
  }

  public static void recordSuccessfulDeltaSync(
    CatalogJobConfig__mdt config,
    Datetime cutoff
  ) {
    String targetKey = buildResolvedTargetKey(config);
    Catalog_Sync_State__c stateRecord = loadStateByTargetKey(targetKey);
    if (stateRecord == null) {
      stateRecord = new Catalog_Sync_State__c();
      stateRecord.ResolvedTargetKey__c = targetKey;
    }

    if (String.isNotBlank(config.BaselineFullConfigDeveloperName__c)) {
      stateRecord.BaselineFullConfigDeveloperName__c = config.BaselineFullConfigDeveloperName__c.trim();
    }
    stateRecord.LastSuccessfulSyncAt__c = cutoff;
    stateRecord.LastRunMode__c = CatalogSyncMode.DELTA;
    stateRecord.LastSuccessfulConfigDeveloperName__c = config.DeveloperName;
    markCurrentRecentProductRunCompleted(
      stateRecord,
      CatalogSyncMode.DELTA,
      config.DeveloperName,
      cutoff
    );
    upsert stateRecord ResolvedTargetKey__c;
  }

  public static void recordStartedProductSync(
    CatalogJobConfig__mdt config,
    String runMode,
    Id jobId,
    Datetime startedAt
  ) {
    if (config == null || jobId == null) {
      return;
    }

    String targetKey = buildResolvedTargetKey(config);
    Catalog_Sync_State__c stateRecord = loadStateByTargetKey(targetKey);
    if (stateRecord == null) {
      stateRecord = new Catalog_Sync_State__c();
      stateRecord.ResolvedTargetKey__c = targetKey;
    }

    if (CatalogSyncMode.isFull(config)) {
      stateRecord.BaselineFullConfigDeveloperName__c = config.DeveloperName;
    } else if (String.isNotBlank(config.BaselineFullConfigDeveloperName__c)) {
      stateRecord.BaselineFullConfigDeveloperName__c = config.BaselineFullConfigDeveloperName__c.trim();
    }

    stateRecord.CurrentProductJobId__c = String.valueOf(jobId);
    stateRecord.CurrentProductRunMode__c = CatalogSyncMode.resolve(runMode);
    stateRecord.CurrentProductConfigDeveloperName__c = config.DeveloperName;
    stateRecord.CurrentProductStartedAt__c = startedAt == null
      ? System.now()
      : startedAt;
    recordRecentProductRunStart(
      stateRecord,
      String.valueOf(jobId),
      runMode,
      config.DeveloperName,
      startedAt
    );

    upsert stateRecord ResolvedTargetKey__c;
  }

  @TestVisible
  private static void clearTestOverrides() {
    testConfigsByDeveloperName = null;
    testStatesByTargetKey = null;
    testAsyncJobStatusesById = null;
    testAsyncJobCreatedDatesById = null;
    testAsyncJobCompletedDatesById = null;
  }

  private static Snapshot buildSnapshot(
    CatalogJobConfig__mdt config,
    CatalogJobConfig__mdt baselineConfig,
    String targetKey,
    String baselineTargetKey,
    Catalog_Sync_State__c stateRecord,
    TrackedAsyncJob trackedJob,
    Map<String, TrackedAsyncJob> trackedJobsById
  ) {
    Snapshot snapshot = new Snapshot();
    snapshot.resolvedTargetKey = targetKey;
    snapshot.syncMode = CatalogSyncMode.resolve(config);
    snapshot.baselineFullConfigDeveloperName = String.isBlank(
        config.BaselineFullConfigDeveloperName__c
      )
      ? null
      : config.BaselineFullConfigDeveloperName__c.trim();
    snapshot.lastSuccessfulFullSyncAt = formatDatetime(
      stateRecord == null ? null : stateRecord.LastSuccessfulFullSyncAt__c
    );
    snapshot.lastSuccessfulSyncAt = formatDatetime(
      stateRecord == null ? null : stateRecord.LastSuccessfulSyncAt__c
    );
    snapshot.lastRunMode = stateRecord == null
      ? null
      : stateRecord.LastRunMode__c;
    snapshot.lastSuccessfulConfigDeveloperName = stateRecord == null
      ? null
      : stateRecord.LastSuccessfulConfigDeveloperName__c;
    if (trackedJob != null && trackedJob.isTerminal != true) {
      snapshot.currentProductJobId = trackedJob.jobId;
      snapshot.currentProductJobStatus = trackedJob.status;
      snapshot.currentProductRunMode = stateRecord.CurrentProductRunMode__c;
      snapshot.currentProductConfigDeveloperName = stateRecord.CurrentProductConfigDeveloperName__c;
      snapshot.currentProductStartedAt = formatDatetime(
        trackedJob.createdDate == null
          ? stateRecord.CurrentProductStartedAt__c
          : trackedJob.createdDate
      );
      snapshot.currentProductIsActive = true;
    } else {
      snapshot.currentProductIsActive = false;
    }
    snapshot.recentProductRuns = buildRecentProductRuns(
      stateRecord,
      trackedJobsById
    );

    if (!CatalogSyncMode.isDelta(config)) {
      snapshot.deltaReady = true;
      snapshot.deltaReadinessMessage = 'Full sync establishes the baseline.';
      return snapshot;
    }

    String readinessFailure = evaluateDeltaReadinessFailure(
      config,
      baselineConfig,
      targetKey,
      baselineTargetKey,
      stateRecord,
      trackedJob
    );
    snapshot.deltaReady = String.isBlank(readinessFailure);
    snapshot.deltaReadinessMessage = snapshot.deltaReady
      ? 'Ready for delta sync.'
      : readinessFailure;
    return snapshot;
  }

  private static String evaluateDeltaReadinessFailure(
    CatalogJobConfig__mdt config,
    CatalogJobConfig__mdt baselineConfig,
    String targetKey,
    String baselineTargetKey,
    Catalog_Sync_State__c stateRecord,
    TrackedAsyncJob trackedJob
  ) {
    if (String.isBlank(config.BaselineFullConfigDeveloperName__c)) {
      return 'BaselineFullConfigDeveloperName__c is required for Delta sync mode.';
    }

    if (baselineConfig == null) {
      return 'Baseline full config "' +
        config.BaselineFullConfigDeveloperName__c.trim() +
        '" was not found.';
    }

    if (!CatalogSyncMode.isFull(baselineConfig)) {
      return 'Baseline full config "' +
        baselineConfig.DeveloperName +
        '" must use SyncMode__c = Full.';
    }

    if (baselineTargetKey != targetKey) {
      return 'Baseline full config "' +
        baselineConfig.DeveloperName +
        '" does not resolve to the same export target as delta config "' +
        config.DeveloperName +
        '".';
    }

    if (
      stateRecord == null ||
      stateRecord.LastSuccessfulFullSyncAt__c == null
    ) {
      return 'Run the baseline full sync once before running delta sync "' +
        config.DeveloperName +
        '".';
    }

    if (
      trackedJob != null &&
      trackedJob.isTerminal != true &&
      stateRecord.CurrentProductRunMode__c == CatalogSyncMode.FULL
    ) {
      String activeFullConfigDeveloperName = String.isBlank(
          stateRecord.CurrentProductConfigDeveloperName__c
        )
        ? baselineConfig.DeveloperName
        : stateRecord.CurrentProductConfigDeveloperName__c;
      return 'Baseline full sync "' +
        activeFullConfigDeveloperName +
        '" is currently running. Wait for it to complete before running delta sync "' +
        config.DeveloperName +
        '".';
    }

    return null;
  }

  private static Map<String, CatalogJobConfig__mdt> loadConfigsByDeveloperName(
    Set<String> developerNames
  ) {
    Map<String, CatalogJobConfig__mdt> configsByDeveloperName = new Map<String, CatalogJobConfig__mdt>();

    if (developerNames == null || developerNames.isEmpty()) {
      return configsByDeveloperName;
    }

    if (Test.isRunningTest() && testConfigsByDeveloperName != null) {
      for (String developerName : developerNames) {
        CatalogJobConfig__mdt config = testConfigsByDeveloperName.get(
          developerName
        );
        if (config != null) {
          configsByDeveloperName.put(developerName, config);
        }
      }
      return configsByDeveloperName;
    }

    for (CatalogJobConfig__mdt config : [
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
      WHERE DeveloperName IN :developerNames
    ]) {
      configsByDeveloperName.put(config.DeveloperName, config);
    }

    return configsByDeveloperName;
  }

  private static Map<String, Catalog_Sync_State__c> loadStatesByTargetKey(
    Set<String> targetKeys
  ) {
    Map<String, Catalog_Sync_State__c> statesByTargetKey = new Map<String, Catalog_Sync_State__c>();

    if (targetKeys == null || targetKeys.isEmpty()) {
      return statesByTargetKey;
    }

    if (Test.isRunningTest() && testStatesByTargetKey != null) {
      for (String targetKey : targetKeys) {
        Catalog_Sync_State__c stateRecord = testStatesByTargetKey.get(
          targetKey
        );
        if (stateRecord != null) {
          statesByTargetKey.put(targetKey, stateRecord);
        }
      }
      return statesByTargetKey;
    }

    for (Catalog_Sync_State__c stateRecord : [
      SELECT
        Id,
        ResolvedTargetKey__c,
        BaselineFullConfigDeveloperName__c,
        CurrentProductJobId__c,
        CurrentProductRunMode__c,
        CurrentProductConfigDeveloperName__c,
        CurrentProductStartedAt__c,
        LastSuccessfulFullSyncAt__c,
        LastSuccessfulSyncAt__c,
        LastRunMode__c,
        LastSuccessfulConfigDeveloperName__c,
        RecentProductRunsJson__c
      FROM Catalog_Sync_State__c
      WHERE ResolvedTargetKey__c IN :targetKeys
    ]) {
      statesByTargetKey.put(stateRecord.ResolvedTargetKey__c, stateRecord);
    }

    return statesByTargetKey;
  }

  private static Catalog_Sync_State__c loadStateByTargetKey(String targetKey) {
    if (String.isBlank(targetKey)) {
      return null;
    }

    if (Test.isRunningTest() && testStatesByTargetKey != null) {
      return testStatesByTargetKey.get(targetKey);
    }

    List<Catalog_Sync_State__c> stateRecords = [
      SELECT
        Id,
        ResolvedTargetKey__c,
        BaselineFullConfigDeveloperName__c,
        CurrentProductJobId__c,
        CurrentProductRunMode__c,
        CurrentProductConfigDeveloperName__c,
        CurrentProductStartedAt__c,
        LastSuccessfulFullSyncAt__c,
        LastSuccessfulSyncAt__c,
        LastRunMode__c,
        LastSuccessfulConfigDeveloperName__c,
        RecentProductRunsJson__c
      FROM Catalog_Sync_State__c
      WHERE ResolvedTargetKey__c = :targetKey
      LIMIT 1
    ];

    return stateRecords.isEmpty() ? null : stateRecords[0];
  }

  private static Map<String, TrackedAsyncJob> loadTrackedJobsById(
    Set<String> jobIds
  ) {
    Map<String, TrackedAsyncJob> jobsById = new Map<String, TrackedAsyncJob>();

    if (jobIds == null || jobIds.isEmpty()) {
      return jobsById;
    }

    if (Test.isRunningTest() && testAsyncJobStatusesById != null) {
      for (String jobId : jobIds) {
        if (!testAsyncJobStatusesById.containsKey(jobId)) {
          continue;
        }

        TrackedAsyncJob trackedJob = new TrackedAsyncJob();
        trackedJob.jobId = jobId;
        trackedJob.status = testAsyncJobStatusesById.get(jobId);
        trackedJob.createdDate = testAsyncJobCreatedDatesById == null
          ? null
          : testAsyncJobCreatedDatesById.get(jobId);
        trackedJob.completedDate = testAsyncJobCompletedDatesById == null
          ? null
          : testAsyncJobCompletedDatesById.get(jobId);
        trackedJob.isTerminal = isTerminalAsyncJobStatus(trackedJob.status);
        jobsById.put(jobId, trackedJob);
      }

      return jobsById;
    }

    Set<Id> validJobIds = new Set<Id>();
    for (String jobId : jobIds) {
      if (String.isBlank(jobId)) {
        continue;
      }

      try {
        validJobIds.add((Id) jobId);
      } catch (Exception e) {
        // Ignore invalid ids so stale tracking records do not break snapshots.
      }
    }

    if (validJobIds.isEmpty()) {
      return jobsById;
    }

    for (AsyncApexJob job : [
      SELECT Id, Status, CreatedDate, CompletedDate
      FROM AsyncApexJob
      WHERE Id IN :validJobIds
    ]) {
      TrackedAsyncJob trackedJob = new TrackedAsyncJob();
      trackedJob.jobId = String.valueOf(job.Id);
      trackedJob.status = job.Status;
      trackedJob.createdDate = job.CreatedDate;
      trackedJob.completedDate = job.CompletedDate;
      trackedJob.isTerminal = isTerminalAsyncJobStatus(job.Status);
      jobsById.put(trackedJob.jobId, trackedJob);
    }

    return jobsById;
  }

  private static Boolean isTerminalAsyncJobStatus(String status) {
    return status == 'Completed' || status == 'Aborted' || status == 'Failed';
  }

  private static void recordRecentProductRunStart(
    Catalog_Sync_State__c stateRecord,
    String jobId,
    String runMode,
    String configDeveloperName,
    Datetime startedAt
  ) {
    if (stateRecord == null || String.isBlank(jobId)) {
      return;
    }

    StoredRecentProductRun recentRun = new StoredRecentProductRun();
    recentRun.jobId = jobId;
    recentRun.runMode = CatalogSyncMode.resolve(runMode);
    recentRun.configDeveloperName = configDeveloperName;
    recentRun.status = 'Queued';
    recentRun.startedAt = formatDatetime(
      startedAt == null ? System.now() : startedAt
    );
    recentRun.completedAt = null;
    stateRecord.RecentProductRunsJson__c = serializeRecentProductRuns(
      upsertRecentProductRun(
        extractStoredRecentProductRuns(stateRecord),
        recentRun
      )
    );
  }

  private static void markCurrentRecentProductRunCompleted(
    Catalog_Sync_State__c stateRecord,
    String runMode,
    String configDeveloperName,
    Datetime completedAt
  ) {
    if (
      stateRecord == null || String.isBlank(stateRecord.CurrentProductJobId__c)
    ) {
      return;
    }

    StoredRecentProductRun recentRun = new StoredRecentProductRun();
    recentRun.jobId = stateRecord.CurrentProductJobId__c;
    recentRun.runMode = CatalogSyncMode.resolve(runMode);
    recentRun.configDeveloperName = configDeveloperName;
    recentRun.status = 'Completed';
    recentRun.startedAt = formatDatetime(
      stateRecord.CurrentProductStartedAt__c
    );
    recentRun.completedAt = formatDatetime(
      completedAt == null ? System.now() : completedAt
    );
    stateRecord.RecentProductRunsJson__c = serializeRecentProductRuns(
      upsertRecentProductRun(
        extractStoredRecentProductRuns(stateRecord),
        recentRun
      )
    );
  }

  private static List<RecentProductRun> buildRecentProductRuns(
    Catalog_Sync_State__c stateRecord,
    Map<String, TrackedAsyncJob> trackedJobsById
  ) {
    List<RecentProductRun> recentProductRuns = new List<RecentProductRun>();

    for (
      StoredRecentProductRun storedRun : extractStoredRecentProductRuns(
        stateRecord
      )
    ) {
      if (String.isBlank(storedRun.jobId)) {
        continue;
      }

      TrackedAsyncJob trackedJob = trackedJobsById == null
        ? null
        : trackedJobsById.get(storedRun.jobId);
      RecentProductRun recentRun = new RecentProductRun();
      recentRun.jobId = storedRun.jobId;
      recentRun.runMode = CatalogSyncMode.resolve(storedRun.runMode);
      recentRun.configDeveloperName = normalizeStoredRecentProductRunValue(
        storedRun.configDeveloperName
      );
      recentRun.status = trackedJob == null
        ? defaultRecentProductRunStatus(storedRun)
        : trackedJob.status;
      recentRun.startedAt = trackedJob != null &&
        trackedJob.createdDate != null
        ? formatDatetime(trackedJob.createdDate)
        : storedRun.startedAt;
      recentRun.completedAt = trackedJob != null &&
        trackedJob.completedDate != null
        ? formatDatetime(trackedJob.completedDate)
        : storedRun.completedAt;
      recentRun.isTerminal = trackedJob != null
        ? trackedJob.isTerminal
        : isTerminalAsyncJobStatus(recentRun.status);
      recentProductRuns.add(recentRun);
    }

    return recentProductRuns;
  }

  private static String defaultRecentProductRunStatus(
    StoredRecentProductRun storedRun
  ) {
    if (String.isNotBlank(storedRun.status)) {
      return storedRun.status;
    }

    return String.isNotBlank(storedRun.completedAt) ? 'Completed' : 'Queued';
  }

  private static List<StoredRecentProductRun> extractStoredRecentProductRuns(
    Catalog_Sync_State__c stateRecord
  ) {
    List<StoredRecentProductRun> recentRuns = parseRecentProductRuns(
      stateRecord == null ? null : stateRecord.RecentProductRunsJson__c
    );

    if (
      stateRecord == null || String.isBlank(stateRecord.CurrentProductJobId__c)
    ) {
      return recentRuns;
    }

    StoredRecentProductRun currentRun = new StoredRecentProductRun();
    currentRun.jobId = stateRecord.CurrentProductJobId__c;
    currentRun.runMode = stateRecord.CurrentProductRunMode__c;
    currentRun.configDeveloperName = stateRecord.CurrentProductConfigDeveloperName__c;
    currentRun.startedAt = formatDatetime(
      stateRecord.CurrentProductStartedAt__c
    );
    return upsertRecentProductRun(recentRuns, currentRun);
  }

  private static List<StoredRecentProductRun> parseRecentProductRuns(
    String jsonValue
  ) {
    List<StoredRecentProductRun> recentRuns = new List<StoredRecentProductRun>();

    if (String.isBlank(jsonValue)) {
      return recentRuns;
    }

    try {
      for (Object rawRun : (List<Object>) JSON.deserializeUntyped(jsonValue)) {
        Map<String, Object> rawFields;
        try {
          rawFields = (Map<String, Object>) rawRun;
        } catch (Exception e) {
          continue;
        }

        StoredRecentProductRun recentRun = new StoredRecentProductRun();
        recentRun.jobId = normalizeStoredRecentProductRunValue(
          rawFields.get('jobId')
        );
        recentRun.runMode = normalizeStoredRecentProductRunValue(
          rawFields.get('runMode')
        );
        recentRun.configDeveloperName = normalizeStoredRecentProductRunValue(
          rawFields.get('configDeveloperName')
        );
        recentRun.status = normalizeStoredRecentProductRunValue(
          rawFields.get('status')
        );
        recentRun.startedAt = normalizeStoredRecentProductRunValue(
          rawFields.get('startedAt')
        );
        recentRun.completedAt = normalizeStoredRecentProductRunValue(
          rawFields.get('completedAt')
        );
        if (String.isNotBlank(recentRun.jobId)) {
          recentRuns.add(recentRun);
        }
      }
    } catch (Exception e) {
      return new List<StoredRecentProductRun>();
    }

    return upsertRecentProductRun(
      new List<StoredRecentProductRun>(),
      null,
      recentRuns
    );
  }

  private static List<StoredRecentProductRun> upsertRecentProductRun(
    List<StoredRecentProductRun> existingRuns,
    StoredRecentProductRun newRun
  ) {
    return upsertRecentProductRun(
      existingRuns,
      newRun,
      new List<StoredRecentProductRun>()
    );
  }

  private static List<StoredRecentProductRun> upsertRecentProductRun(
    List<StoredRecentProductRun> existingRuns,
    StoredRecentProductRun newRun,
    List<StoredRecentProductRun> additionalRuns
  ) {
    Map<String, StoredRecentProductRun> existingRunsByJobId = new Map<String, StoredRecentProductRun>();
    List<String> orderedJobIds = new List<String>();

    for (StoredRecentProductRun existingRun : existingRuns) {
      if (existingRun == null || String.isBlank(existingRun.jobId)) {
        continue;
      }

      existingRunsByJobId.put(existingRun.jobId, existingRun);
      if (!orderedJobIds.contains(existingRun.jobId)) {
        orderedJobIds.add(existingRun.jobId);
      }
    }

    List<StoredRecentProductRun> mergedRuns = new List<StoredRecentProductRun>();
    Set<String> includedJobIds = new Set<String>();
    List<StoredRecentProductRun> preferredRuns = new List<StoredRecentProductRun>();

    if (newRun != null && String.isNotBlank(newRun.jobId)) {
      preferredRuns.add(newRun);
    }
    preferredRuns.addAll(additionalRuns);

    for (StoredRecentProductRun preferredRun : preferredRuns) {
      if (preferredRun == null || String.isBlank(preferredRun.jobId)) {
        continue;
      }

      if (includedJobIds.contains(preferredRun.jobId)) {
        continue;
      }

      mergedRuns.add(
        mergeStoredRecentProductRun(
          preferredRun,
          existingRunsByJobId.get(preferredRun.jobId)
        )
      );
      includedJobIds.add(preferredRun.jobId);
      if (mergedRuns.size() >= MAX_RECENT_PRODUCT_RUNS) {
        return mergedRuns;
      }
    }

    for (String jobId : orderedJobIds) {
      if (includedJobIds.contains(jobId)) {
        continue;
      }

      mergedRuns.add(
        mergeStoredRecentProductRun(existingRunsByJobId.get(jobId), null)
      );
      includedJobIds.add(jobId);
      if (mergedRuns.size() >= MAX_RECENT_PRODUCT_RUNS) {
        break;
      }
    }

    return mergedRuns;
  }

  private static StoredRecentProductRun mergeStoredRecentProductRun(
    StoredRecentProductRun preferredRun,
    StoredRecentProductRun fallbackRun
  ) {
    StoredRecentProductRun mergedRun = new StoredRecentProductRun();
    mergedRun.jobId = firstNonBlank(
      preferredRun == null ? null : preferredRun.jobId,
      fallbackRun == null ? null : fallbackRun.jobId
    );
    mergedRun.runMode = CatalogSyncMode.resolve(
      firstNonBlank(
        preferredRun == null ? null : preferredRun.runMode,
        fallbackRun == null ? null : fallbackRun.runMode
      )
    );
    mergedRun.configDeveloperName = firstNonBlank(
      preferredRun == null ? null : preferredRun.configDeveloperName,
      fallbackRun == null ? null : fallbackRun.configDeveloperName
    );
    mergedRun.status = firstNonBlank(
      preferredRun == null ? null : preferredRun.status,
      fallbackRun == null ? null : fallbackRun.status
    );
    mergedRun.startedAt = firstNonBlank(
      preferredRun == null ? null : preferredRun.startedAt,
      fallbackRun == null ? null : fallbackRun.startedAt
    );
    mergedRun.completedAt = firstNonBlank(
      preferredRun == null ? null : preferredRun.completedAt,
      fallbackRun == null ? null : fallbackRun.completedAt
    );
    return mergedRun;
  }

  private static String serializeRecentProductRuns(
    List<StoredRecentProductRun> recentRuns
  ) {
    return recentRuns == null || recentRuns.isEmpty()
      ? null
      : JSON.serialize(recentRuns);
  }

  private static String firstNonBlank(
    String primaryValue,
    String fallbackValue
  ) {
    return String.isNotBlank(primaryValue) ? primaryValue : fallbackValue;
  }

  private static String normalizeStoredRecentProductRunValue(Object rawValue) {
    return rawValue == null ? null : String.valueOf(rawValue).trim();
  }

  private static String canonicalizeCsv(String csvValue) {
    List<String> normalizedValues = new List<String>();

    if (String.isBlank(csvValue)) {
      return '';
    }

    for (String token : csvValue.split(',')) {
      String normalizedToken = normalizeText(token).toLowerCase();
      if (
        String.isNotBlank(normalizedToken) &&
        !normalizedValues.contains(normalizedToken)
      ) {
        normalizedValues.add(normalizedToken);
      }
    }

    normalizedValues.sort();
    return String.join(normalizedValues, ',');
  }

  private static String canonicalizeIdCsv(String csvValue, String fieldName) {
    if (String.isBlank(csvValue)) {
      return '';
    }

    Set<Id> recordIds = new Set<Id>();
    for (String rawValue : csvValue.split('[,;\\n\\r]+')) {
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

    List<String> normalizedIds = new List<String>();
    for (Id recordId : recordIds) {
      normalizedIds.add(String.valueOf(recordId));
    }
    normalizedIds.sort();
    return String.join(normalizedIds, ',');
  }

  private static String normalizeText(String value) {
    return String.isBlank(value) ? '' : value.trim();
  }

  private static String formatDatetime(Datetime value) {
    return value == null
      ? null
      : value.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
  }
}
