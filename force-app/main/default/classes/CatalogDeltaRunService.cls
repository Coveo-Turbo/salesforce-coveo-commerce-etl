public with sharing class CatalogDeltaRunService {
  public static final String STATUS_QUEUED = 'Queued';
  public static final String STATUS_RUNNING = 'Running';
  public static final String STATUS_SUCCEEDED = 'Succeeded';
  public static final String STATUS_FAILED = 'Failed';
  public static final String STATUS_CANCEL_REQUESTED = 'CancelRequested';
  public static final String STATUS_CANCELED = 'Canceled';

  public static final String CLEANUP_PENDING = 'Pending';
  public static final String CLEANUP_RUNNING = 'Running';
  public static final String CLEANUP_COMPLETED = 'Completed';
  public static final String CLEANUP_FAILED = 'Failed';

  public static final Integer DISCOVERY_BATCH_SIZE = 500;

  @TestVisible
  private static Boolean suppressChainingInTests = true;
  @TestVisible
  private static String lastRequestedStage;
  @TestVisible
  private static Integer lastRequestedDepth;

  public class LaunchResult {
    public Id runId { get; set; }
    public Id jobId { get; set; }
  }

  public class Snapshot {
    public String runId { get; set; }
    public String jobId { get; set; }
    public String initialJobId { get; set; }
    public String status { get; set; }
    public String stage { get; set; }
    public String stageLabel { get; set; }
    public Integer impactedProductCount { get; set; }
    public Integer rootProductCount { get; set; }
    public Integer exportProductCount { get; set; }
    public String scopeSummary { get; set; }
    public Integer jobItemsProcessed { get; set; }
    public Integer totalJobItems { get; set; }
    public Integer numberOfErrors { get; set; }
    public String extendedStatus { get; set; }
    public Boolean isTerminal { get; set; }
    public String createdDate { get; set; }
    public String completedDate { get; set; }
  }

  public static LaunchResult launch(CatalogJobConfig__mdt config) {
    CatalogSyncStateService.DeltaReadiness readiness = CatalogSyncStateService.requireDeltaReadiness(
      config
    );
    return launch(
      config,
      readiness.stateRecord.LastSuccessfulSyncAt__c,
      System.now()
    );
  }

  @TestVisible
  public static LaunchResult launch(
    CatalogJobConfig__mdt config,
    Datetime baselineTimestamp,
    Datetime cutoffTimestamp
  ) {
    if (config == null || !CatalogSyncMode.isDelta(config)) {
      throw new CatalogJobConfigException(
        'A Delta CatalogJobConfig__mdt record is required.'
      );
    }
    if (
      baselineTimestamp == null ||
      cutoffTimestamp == null ||
      baselineTimestamp.getTime() >= cutoffTimestamp.getTime()
    ) {
      throw new CatalogJobConfigException(
        'Delta baseline and cutoff timestamps must define a non-empty forward interval.'
      );
    }

    String targetKey = CatalogSyncStateService.buildResolvedTargetKey(config);
    Catalog_Sync_State__c lockedState = lockTargetState(targetKey, false);
    rejectActiveTrackedProductJob(lockedState, config.DeveloperName);
    reconcileOrRejectActiveRun(targetKey, config.DeveloperName);

    Id standardPricebookId = ProductCatalogExportBatch.getStandardPricebookId();
    WebStorePricebookResolver.PricebookResolution pricebookResolution = WebStorePricebookResolver.resolve(
      config
    );

    Catalog_Delta_Run__c run = new Catalog_Delta_Run__c(
      ResolvedTargetKey__c = targetKey,
      ConfigDeveloperName__c = config.DeveloperName,
      BaselineTimestamp__c = baselineTimestamp,
      CutoffTimestamp__c = cutoffTimestamp,
      Status__c = STATUS_QUEUED,
      Stage__c = CatalogDeltaStageBatch.DISCOVER_PRODUCTS,
      LastHeartbeatAt__c = System.now(),
      ImpactedProductCount__c = 0,
      RootProductCount__c = 0,
      ExportProductCount__c = 0,
      PricebookScopeFiltered__c = pricebookResolution.isFiltered,
      ResolvedPricebookIdsJson__c = serializeIds(
        pricebookResolution.pricebookIds
      ),
      PricebookLabelsJson__c = serializeLabels(
        pricebookResolution.labelsByPricebookId
      ),
      StandardPricebookId__c = standardPricebookId,
      CleanupStatus__c = CLEANUP_PENDING
    );
    insert run;

    CatalogDeltaStageBatch firstStage = new CatalogDeltaStageBatch(
      run.Id,
      CatalogDeltaStageBatch.DISCOVER_PRODUCTS,
      0,
      config
    );
    Id firstJobId = Database.executeBatch(firstStage, DISCOVERY_BATCH_SIZE);

    run.Status__c = STATUS_RUNNING;
    run.InitialAsyncJobId__c = String.valueOf(firstJobId);
    run.CurrentAsyncJobId__c = String.valueOf(firstJobId);
    update run;

    CatalogSyncStateService.recordStartedDeltaPipeline(
      config,
      run.Id,
      firstJobId,
      System.now()
    );

    LaunchResult result = new LaunchResult();
    result.runId = run.Id;
    result.jobId = firstJobId;
    return result;
  }

  public static void assertNoActiveDeltaRun(CatalogJobConfig__mdt config) {
    if (config == null) {
      return;
    }
    String targetKey = CatalogSyncStateService.buildResolvedTargetKey(config);
    Catalog_Sync_State__c lockedState = lockTargetState(targetKey, true);
    reconcileOrRejectActiveRun(targetKey, config.DeveloperName);
    rejectActiveTrackedProductJob(lockedState, config.DeveloperName);
  }

  public static void claimFullRun(CatalogJobConfig__mdt config, Id jobId) {
    if (config == null || jobId == null) {
      return;
    }
    String targetKey = CatalogSyncStateService.buildResolvedTargetKey(config);
    Catalog_Sync_State__c lockedState = lockTargetState(targetKey, true);
    List<Catalog_Delta_Run__c> activeRuns = loadActiveRuns(targetKey, false);
    if (!activeRuns.isEmpty()) {
      throw new CatalogJobConfigException(
        'Delta sync "' +
          activeRuns[0].ConfigDeveloperName__c +
          '" is currently running for this export target.'
      );
    }

    AsyncApexJob trackedJob = loadAsyncJob(lockedState.CurrentProductJobId__c);
    if (
      trackedJob != null &&
      trackedJob.Status != 'Completed' &&
      trackedJob.Status != 'Failed' &&
      trackedJob.Status != 'Aborted' &&
      trackedJob.Id != jobId
    ) {
      throw new CatalogJobConfigException(
        'Another product sync already owns this export target.'
      );
    }
    if (lockedState.CurrentProductJobId__c != String.valueOf(jobId)) {
      CatalogSyncStateService.recordStartedProductSync(
        config,
        CatalogSyncMode.FULL,
        jobId,
        System.now()
      );
    }
  }

  public static Id enqueueStage(
    Id runId,
    String stage,
    Integer depth,
    CatalogJobConfig__mdt config
  ) {
    lastRequestedStage = stage;
    lastRequestedDepth = depth;
    if (Test.isRunningTest() && suppressChainingInTests) {
      updateStageWithoutJob(runId, stage);
      return null;
    }

    Id jobId = Database.executeBatch(
      new CatalogDeltaStageBatch(runId, stage, depth, config),
      DISCOVERY_BATCH_SIZE
    );
    updateCurrentStage(runId, stage, jobId);
    return jobId;
  }

  public static Id enqueueExport(Id runId, CatalogJobConfig__mdt config) {
    lastRequestedStage = CatalogDeltaStageBatch.EXPORT_PRODUCTS;
    lastRequestedDepth = null;
    if (Test.isRunningTest() && suppressChainingInTests) {
      updateStageWithoutJob(runId, CatalogDeltaStageBatch.EXPORT_PRODUCTS);
      return null;
    }

    DeltaProductCatalogExportBatch exportBatch = new DeltaProductCatalogExportBatch(
      runId,
      config
    );
    Id jobId = Database.executeBatch(exportBatch, exportBatch.getBatchSize());
    updateCurrentStage(runId, CatalogDeltaStageBatch.EXPORT_PRODUCTS, jobId);
    return jobId;
  }

  public static void completeRun(
    Id runId,
    CatalogJobConfig__mdt config,
    Integer exportedProductCount
  ) {
    Catalog_Delta_Run__c run = loadRunForUpdate(runId);
    if (run.Status__c == STATUS_CANCEL_REQUESTED) {
      markCanceled(run, 'Cancellation requested before delta completion.');
      tryEnqueueCleanup(run.Id);
      return;
    }
    if (run.Status__c != STATUS_RUNNING) {
      return;
    }

    String currentTargetKey = CatalogSyncStateService.buildResolvedTargetKey(config);
    if (currentTargetKey != run.ResolvedTargetKey__c) {
      markFailed(
        run,
        'Catalog configuration changed the resolved target while the delta run was active.'
      );
      tryEnqueueCleanup(run.Id);
      return;
    }

    run.Status__c = STATUS_SUCCEEDED;
    run.Stage__c = CatalogDeltaStageBatch.EXPORT_PRODUCTS;
    run.ExportProductCount__c = exportedProductCount == null
      ? 0
      : exportedProductCount;
    run.CompletedAt__c = System.now();
    run.LastHeartbeatAt__c = System.now();
    update run;

    CatalogSyncStateService.recordSuccessfulDeltaPipeline(
      config,
      run.Id,
      run.InitialAsyncJobId__c,
      run.CutoffTimestamp__c
    );
    tryEnqueueCleanup(run.Id);
  }

  public static void failRun(Id runId, String errorMessage) {
    Catalog_Delta_Run__c run = loadRunForUpdate(runId);
    if (isTerminalStatus(run.Status__c)) {
      return;
    }
    if (run.Status__c == STATUS_CANCEL_REQUESTED) {
      markCanceled(run, errorMessage);
      tryEnqueueCleanup(run.Id);
      return;
    }
    markFailed(run, errorMessage);
    tryEnqueueCleanup(run.Id);
  }

  public static String cancelRun(Id runId) {
    Catalog_Delta_Run__c run = loadRunForUpdate(runId);
    if (isTerminalStatus(run.Status__c)) {
      return run.CurrentAsyncJobId__c;
    }

    run.Status__c = STATUS_CANCEL_REQUESTED;
    run.ErrorMessage__c = 'Cancellation requested by an administrator.';
    run.LastHeartbeatAt__c = System.now();
    update run;

    String currentJobId = run.CurrentAsyncJobId__c;
    if (String.isNotBlank(currentJobId)) {
      try {
        System.abortJob((Id) currentJobId);
      } catch (Exception e) {
        // A stage may finish between the lock and abort. The persisted cancel
        // request prevents its finish method from launching another stage.
      }
    }

    return currentJobId;
  }

  public static void applyMetricDeltas(
    Id runId,
    Integer impactedDelta,
    Integer rootDelta
  ) {
    Catalog_Delta_Run__c run = loadRunForUpdate(runId);
    run.ImpactedProductCount__c = (run.ImpactedProductCount__c == null
        ? 0
        : run.ImpactedProductCount__c) +
      (impactedDelta == null ? 0 : impactedDelta);
    run.RootProductCount__c = (run.RootProductCount__c == null
        ? 0
        : run.RootProductCount__c) +
      (rootDelta == null ? 0 : rootDelta);
    run.LastHeartbeatAt__c = System.now();
    update run;
  }

  public static Catalog_Delta_Run__c loadRun(Id runId) {
    List<Catalog_Delta_Run__c> runs = queryRuns(new Set<Id>{ runId }, false);
    if (runs.isEmpty()) {
      throw new CatalogJobException('Catalog delta run not found: ' + runId);
    }
    return runs[0];
  }

  public static Set<Id> getResolvedPricebookIds(Catalog_Delta_Run__c run) {
    if (run == null || run.PricebookScopeFiltered__c != true) {
      return null;
    }
    Set<Id> result = new Set<Id>();
    if (String.isBlank(run.ResolvedPricebookIdsJson__c)) {
      return result;
    }
    for (
      Object value : (List<Object>) JSON.deserializeUntyped(
        run.ResolvedPricebookIdsJson__c
      )
    ) {
      result.add((Id) String.valueOf(value));
    }
    return result;
  }

  public static Map<Id, String> getPricebookLabels(Catalog_Delta_Run__c run) {
    Map<Id, String> result = new Map<Id, String>();
    if (run == null || String.isBlank(run.PricebookLabelsJson__c)) {
      return result;
    }
    Map<String, Object> rawLabels = (Map<String, Object>) JSON.deserializeUntyped(
      run.PricebookLabelsJson__c
    );
    for (String pricebookId : rawLabels.keySet()) {
      result.put((Id) pricebookId, String.valueOf(rawLabels.get(pricebookId)));
    }
    return result;
  }

  public static List<Snapshot> getSnapshots(List<String> runIds) {
    Set<Id> validRunIds = new Set<Id>();
    if (runIds != null) {
      for (String runId : runIds) {
        try {
          if (String.isNotBlank(runId)) {
            validRunIds.add((Id) runId);
          }
        } catch (Exception e) {
          // Ignore invalid persisted browser values and continue polling others.
        }
      }
    }
    if (validRunIds.isEmpty()) {
      return new List<Snapshot>();
    }

    Map<Id, Catalog_Delta_Run__c> runsById = new Map<Id, Catalog_Delta_Run__c>(
      queryRuns(validRunIds, false)
    );
    Set<Id> currentJobIds = new Set<Id>();
    for (Catalog_Delta_Run__c run : runsById.values()) {
      try {
        if (String.isNotBlank(run.CurrentAsyncJobId__c)) {
          currentJobIds.add((Id) run.CurrentAsyncJobId__c);
        }
      } catch (Exception e) {
        // Keep run-level state usable if a stale job ID was persisted.
      }
    }
    Map<Id, AsyncApexJob> jobsById = currentJobIds.isEmpty()
      ? new Map<Id, AsyncApexJob>()
      : new Map<Id, AsyncApexJob>([
          SELECT
            Id,
            Status,
            JobItemsProcessed,
            TotalJobItems,
            NumberOfErrors,
            ExtendedStatus,
            CreatedDate,
            CompletedDate
          FROM AsyncApexJob
          WHERE Id IN :currentJobIds
        ]);

    for (Id currentRunId : new Set<Id>(runsById.keySet())) {
      Catalog_Delta_Run__c run = runsById.get(currentRunId);
      AsyncApexJob currentJob;
      try {
        currentJob = jobsById.get((Id) run.CurrentAsyncJobId__c);
      } catch (Exception e) {
        currentJob = null;
      }
      if (
        !isTerminalStatus(run.Status__c) &&
        (currentJob == null ||
        currentJob.Status == 'Completed' ||
        currentJob.Status == 'Failed' ||
        currentJob.Status == 'Aborted')
      ) {
        if (run.Status__c == STATUS_CANCEL_REQUESTED) {
          failRun(run.Id, 'Canceled by an administrator.');
        } else {
          failRun(
            run.Id,
            'The current Async Apex stage ended before the delta pipeline completed.'
          );
        }
        runsById.put(run.Id, loadRun(run.Id));
      }
    }

    List<Snapshot> snapshots = new List<Snapshot>();
    for (String requestedId : runIds) {
      Id parsedId;
      try {
        parsedId = (Id) requestedId;
      } catch (Exception e) {
        continue;
      }
      Catalog_Delta_Run__c run = runsById.get(parsedId);
      if (run == null) {
        continue;
      }
      AsyncApexJob job;
      try {
        job = jobsById.get((Id) run.CurrentAsyncJobId__c);
      } catch (Exception e) {
        job = null;
      }
      snapshots.add(buildSnapshot(run, job));
    }
    return snapshots;
  }

  public static Boolean isTerminalStatus(String status) {
    return status == STATUS_SUCCEEDED ||
      status == STATUS_FAILED ||
      status == STATUS_CANCELED;
  }

  private static Snapshot buildSnapshot(
    Catalog_Delta_Run__c run,
    AsyncApexJob job
  ) {
    Snapshot snapshot = new Snapshot();
    snapshot.runId = String.valueOf(run.Id);
    snapshot.jobId = run.CurrentAsyncJobId__c;
    snapshot.initialJobId = run.InitialAsyncJobId__c;
    snapshot.stage = run.Stage__c;
    snapshot.stageLabel = describeStage(run.Stage__c);
    snapshot.impactedProductCount = decimalToInteger(
      run.ImpactedProductCount__c
    );
    snapshot.rootProductCount = decimalToInteger(run.RootProductCount__c);
    snapshot.exportProductCount = decimalToInteger(run.ExportProductCount__c);
    snapshot.isTerminal = isTerminalStatus(run.Status__c);
    snapshot.status = resolveSnapshotStatus(run, job);
    snapshot.jobItemsProcessed = job == null ? 0 : job.JobItemsProcessed;
    snapshot.totalJobItems = job == null ? 0 : job.TotalJobItems;
    snapshot.numberOfErrors = job == null ? 0 : job.NumberOfErrors;
    snapshot.extendedStatus = String.isNotBlank(run.ErrorMessage__c)
      ? run.ErrorMessage__c
      : job == null ? null : job.ExtendedStatus;
    snapshot.scopeSummary = buildScopeSummary(run);
    snapshot.createdDate = formatDatetime(run.CreatedDate);
    snapshot.completedDate = formatDatetime(run.CompletedAt__c);
    return snapshot;
  }

  private static String resolveSnapshotStatus(
    Catalog_Delta_Run__c run,
    AsyncApexJob job
  ) {
    if (run.Status__c == STATUS_SUCCEEDED) {
      return 'Completed';
    }
    if (run.Status__c == STATUS_FAILED) {
      return 'Failed';
    }
    if (
      run.Status__c == STATUS_CANCELED ||
      run.Status__c == STATUS_CANCEL_REQUESTED
    ) {
      return 'Aborted';
    }
    if (job != null && job.Status != 'Completed') {
      return job.Status;
    }
    return run.Status__c == STATUS_RUNNING ? 'Processing' : 'Queued';
  }

  private static String buildScopeSummary(Catalog_Delta_Run__c run) {
    Integer impacted = decimalToInteger(run.ImpactedProductCount__c);
    Integer roots = decimalToInteger(run.RootProductCount__c);
    Integer exported = decimalToInteger(run.ExportProductCount__c);
    if (run.Stage__c == CatalogDeltaStageBatch.EXPORT_PRODUCTS || isTerminalStatus(run.Status__c)) {
      if (exported == 0 && impacted == 0) {
        return 'No changed products since last sync';
      }
      return impacted +
        ' impacted product' +
        (impacted == 1 ? '' : 's') +
        ' • ' +
        roots +
        ' changed root' +
        (roots == 1 ? '' : 's') +
        ' • ' +
        exported +
        ' product' +
        (exported == 1 ? '' : 's') +
        ' exported';
    }
    return describeStage(run.Stage__c);
  }

  public static String describeStage(String stage) {
    if (stage == CatalogDeltaStageBatch.DISCOVER_PRODUCTS) {
      return 'Discovering product changes';
    }
    if (stage == CatalogDeltaStageBatch.DISCOVER_PRICES) {
      return 'Discovering scoped price changes';
    }
    if (stage == CatalogDeltaStageBatch.DISCOVER_ASSIGNMENTS) {
      return 'Discovering category assignment changes';
    }
    if (
      stage == CatalogDeltaStageBatch.DISCOVER_CATEGORIES ||
      stage == CatalogDeltaStageBatch.EXPAND_CATEGORIES ||
      stage == CatalogDeltaStageBatch.FAN_OUT_CATEGORY_PRODUCTS
    ) {
      return 'Expanding changed categories';
    }
    if (
      stage == CatalogDeltaStageBatch.RESOLVE_ROOTS ||
      stage == CatalogDeltaStageBatch.EXPAND_GROUP_MEMBERS ||
      stage == CatalogDeltaStageBatch.EXPAND_CHILDREN
    ) {
      return 'Resolving changed product families';
    }
    if (stage == CatalogDeltaStageBatch.EXPORT_PRODUCTS) {
      return 'Exporting changed products';
    }
    return String.isBlank(stage) ? 'Preparing delta sync' : stage;
  }

  private static void updateCurrentStage(Id runId, String stage, Id jobId) {
    Catalog_Delta_Run__c run = loadRunForUpdate(runId);
    if (run.Status__c == STATUS_CANCEL_REQUESTED) {
      if (jobId != null) {
        System.abortJob(jobId);
      }
      markCanceled(run, 'Canceled before the next delta stage started.');
      tryEnqueueCleanup(run.Id);
      return;
    }
    run.Status__c = STATUS_RUNNING;
    run.Stage__c = stage;
    run.CurrentAsyncJobId__c = String.valueOf(jobId);
    run.LastHeartbeatAt__c = System.now();
    update run;
    CatalogSyncStateService.recordDeltaPipelineStage(
      run.ResolvedTargetKey__c,
      run.Id,
      jobId
    );
  }

  private static void updateStageWithoutJob(Id runId, String stage) {
    Catalog_Delta_Run__c run = loadRunForUpdate(runId);
    if (!isTerminalStatus(run.Status__c)) {
      run.Stage__c = stage;
      run.LastHeartbeatAt__c = System.now();
      update run;
    }
  }

  private static void enqueueCleanup(Id runId) {
    if (Test.isRunningTest() && suppressChainingInTests) {
      return;
    }
    Catalog_Delta_Run__c currentRun = loadRun(runId);
    if (
      currentRun.CleanupStatus__c == CLEANUP_RUNNING ||
      currentRun.CleanupStatus__c == CLEANUP_COMPLETED
    ) {
      return;
    }
    Id cleanupJobId = Database.executeBatch(
      new CatalogDeltaCleanupBatch(runId),
      2000
    );
    Catalog_Delta_Run__c run = new Catalog_Delta_Run__c(
      Id = runId,
      CleanupStatus__c = CLEANUP_RUNNING,
      CleanupAsyncJobId__c = String.valueOf(cleanupJobId)
    );
    update run;
  }

  private static void tryEnqueueCleanup(Id runId) {
    try {
      enqueueCleanup(runId);
    } catch (Exception e) {
      update new Catalog_Delta_Run__c(
        Id = runId,
        CleanupStatus__c = CLEANUP_FAILED,
        ErrorMessage__c = ('Staging cleanup could not be queued: ' + e.getMessage())
          .left(32768),
        LastHeartbeatAt__c = System.now()
      );
    }
  }

  private static void markFailed(Catalog_Delta_Run__c run, String message) {
    run.Status__c = STATUS_FAILED;
    run.ErrorMessage__c = String.isBlank(message)
      ? 'A delta pipeline stage failed.'
      : message.left(32768);
    run.CompletedAt__c = System.now();
    run.LastHeartbeatAt__c = System.now();
    update run;
  }

  private static void markCanceled(Catalog_Delta_Run__c run, String message) {
    run.Status__c = STATUS_CANCELED;
    run.ErrorMessage__c = message == null ? null : message.left(32768);
    run.CompletedAt__c = System.now();
    run.LastHeartbeatAt__c = System.now();
    update run;
  }

  private static Catalog_Sync_State__c lockTargetState(
    String targetKey,
    Boolean createIfMissing
  ) {
    List<Catalog_Sync_State__c> states = [
      SELECT Id, CurrentProductJobId__c, CurrentProductRunMode__c
      FROM Catalog_Sync_State__c
      WHERE ResolvedTargetKey__c = :targetKey
      LIMIT 1
      FOR UPDATE
    ];
    if (states.isEmpty() && createIfMissing) {
      insert new Catalog_Sync_State__c(ResolvedTargetKey__c = targetKey);
      states = [
        SELECT Id, CurrentProductJobId__c, CurrentProductRunMode__c
        FROM Catalog_Sync_State__c
        WHERE ResolvedTargetKey__c = :targetKey
        LIMIT 1
        FOR UPDATE
      ];
    }
    if (states.isEmpty()) {
      throw new CatalogJobConfigException(
        'Run the matching full sync before launching a delta pipeline.'
      );
    }
    return states[0];
  }

  private static void rejectActiveTrackedProductJob(
    Catalog_Sync_State__c stateRecord,
    String requestedConfigDeveloperName
  ) {
    AsyncApexJob trackedJob = stateRecord == null
      ? null
      : loadAsyncJob(stateRecord.CurrentProductJobId__c);
    if (
      trackedJob == null ||
      trackedJob.Status == 'Completed' ||
      trackedJob.Status == 'Failed' ||
      trackedJob.Status == 'Aborted'
    ) {
      return;
    }
    throw new CatalogJobConfigException(
      'A ' +
        CatalogSyncMode.resolve(stateRecord.CurrentProductRunMode__c).toLowerCase() +
        ' product sync is already running for this export target. Wait for it to finish before launching "' +
        requestedConfigDeveloperName +
        '".'
    );
  }

  private static void reconcileOrRejectActiveRun(
    String targetKey,
    String requestedConfigDeveloperName
  ) {
    // The caller already owns the target-state row lock. Avoid taking an
    // active run lock here because stage completion locks run then state.
    List<Catalog_Delta_Run__c> activeRuns = loadActiveRuns(targetKey, false);
    if (activeRuns.isEmpty()) {
      return;
    }

    Catalog_Delta_Run__c activeRun = activeRuns[0];
    AsyncApexJob currentJob = loadAsyncJob(activeRun.CurrentAsyncJobId__c);
    if (
      currentJob == null ||
      currentJob.Status == 'Completed' ||
      currentJob.Status == 'Failed' ||
      currentJob.Status == 'Aborted'
    ) {
      markFailed(
        activeRun,
        'The previous delta pipeline stopped before reaching a terminal run state.'
      );
      tryEnqueueCleanup(activeRun.Id);
      return;
    }

    throw new CatalogJobConfigException(
      'Delta sync "' +
        activeRun.ConfigDeveloperName__c +
        '" is already running for the same export target. Wait for it to finish before launching "' +
        requestedConfigDeveloperName +
        '".'
    );
  }

  private static AsyncApexJob loadAsyncJob(String jobId) {
    if (String.isBlank(jobId)) {
      return null;
    }
    Id parsedId;
    try {
      parsedId = (Id) jobId;
    } catch (Exception e) {
      return null;
    }
    List<AsyncApexJob> jobs = [
      SELECT Id, Status
      FROM AsyncApexJob
      WHERE Id = :parsedId
      LIMIT 1
    ];
    return jobs.isEmpty() ? null : jobs[0];
  }

  private static List<Catalog_Delta_Run__c> loadActiveRuns(
    String targetKey,
    Boolean forUpdate
  ) {
    Set<String> activeStatuses = new Set<String>{
      STATUS_QUEUED,
      STATUS_RUNNING,
      STATUS_CANCEL_REQUESTED
    };
    String query =
      'SELECT Id, ConfigDeveloperName__c, Status__c, CurrentAsyncJobId__c, ' +
      'ErrorMessage__c, CompletedAt__c, LastHeartbeatAt__c ' +
      'FROM Catalog_Delta_Run__c WHERE ResolvedTargetKey__c = :targetKey ' +
      'AND Status__c IN :activeStatuses';
    if (forUpdate) {
      query += ' LIMIT 1 FOR UPDATE';
    } else {
      query += ' ORDER BY CreatedDate DESC LIMIT 1';
    }
    return Database.query(query);
  }

  private static Catalog_Delta_Run__c loadRunForUpdate(Id runId) {
    List<Catalog_Delta_Run__c> runs = queryRuns(new Set<Id>{ runId }, true);
    if (runs.isEmpty()) {
      throw new CatalogJobException('Catalog delta run not found: ' + runId);
    }
    return runs[0];
  }

  private static List<Catalog_Delta_Run__c> queryRuns(
    Set<Id> runIds,
    Boolean forUpdate
  ) {
    String query =
      'SELECT Id, CreatedDate, ResolvedTargetKey__c, ConfigDeveloperName__c, ' +
      'BaselineTimestamp__c, CutoffTimestamp__c, Status__c, Stage__c, ' +
      'InitialAsyncJobId__c, CurrentAsyncJobId__c, CompletedAt__c, ' +
      'LastHeartbeatAt__c, ErrorMessage__c, ImpactedProductCount__c, ' +
      'RootProductCount__c, ExportProductCount__c, PricebookScopeFiltered__c, ' +
      'ResolvedPricebookIdsJson__c, PricebookLabelsJson__c, ' +
      'StandardPricebookId__c, CleanupStatus__c, CleanupAsyncJobId__c ' +
      'FROM Catalog_Delta_Run__c WHERE Id IN :runIds';
    if (forUpdate) {
      query += ' FOR UPDATE';
    }
    return Database.query(query);
  }

  private static String serializeIds(Set<Id> ids) {
    if (ids == null) {
      return null;
    }
    List<String> values = new List<String>();
    for (Id recordId : ids) {
      values.add(String.valueOf(recordId));
    }
    values.sort();
    return JSON.serialize(values);
  }

  private static String serializeLabels(Map<Id, String> labelsById) {
    if (labelsById == null) {
      return null;
    }
    Map<String, String> values = new Map<String, String>();
    for (Id recordId : labelsById.keySet()) {
      values.put(String.valueOf(recordId), labelsById.get(recordId));
    }
    return JSON.serialize(values);
  }

  private static Integer decimalToInteger(Decimal value) {
    return value == null ? 0 : value.intValue();
  }

  private static String formatDatetime(Datetime value) {
    return value == null
      ? null
      : value.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
  }
}
