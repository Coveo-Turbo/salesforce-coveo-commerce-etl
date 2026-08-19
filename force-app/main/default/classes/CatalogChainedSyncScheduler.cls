global with sharing class CatalogChainedSyncScheduler implements Schedulable {
  @TestVisible
  private static final String JOB_NAME_PREFIX = 'Catalog Chained Sync';
  @TestVisible
  private static final String MINUTE_JOB_NAME_SEPARATOR = ' [Minute ';
  private static final Set<String> TERMINAL_JOB_STATES = new Set<String>{
    'COMPLETE',
    'DELETED',
    'ERROR'
  };

  @TestVisible
  private static Boolean skipQueueableExecutionInTests = false;
  @TestVisible
  private static List<String> lastExecutedConfigDeveloperNames;
  @TestVisible
  private static String lastExecutedSyncMode;
  @TestVisible
  private static Boolean lastExecutedRunProducts;
  @TestVisible
  private static Boolean lastExecutedIncludeAvailability;

  private String chainName;
  private List<String> configDeveloperNames;
  private String syncMode;
  private Boolean runProducts;
  private Boolean includeAvailability;

  global CatalogChainedSyncScheduler() {
  }

  public CatalogChainedSyncScheduler(
    List<String> configDeveloperNames,
    String syncMode,
    Boolean includeAvailability
  ) {
    this(null, configDeveloperNames, syncMode, true, includeAvailability);
  }

  public CatalogChainedSyncScheduler(
    String chainName,
    List<String> configDeveloperNames,
    String syncMode,
    Boolean runProducts,
    Boolean includeAvailability
  ) {
    this.chainName = normalizeChainName(chainName);
    this.configDeveloperNames = CatalogSyncChainQueueable.normalizeConfigDeveloperNames(
      configDeveloperNames
    );
    this.syncMode = String.isBlank(syncMode)
      ? null
      : CatalogSyncMode.resolve(syncMode);
    this.runProducts = runProducts == true;
    this.includeAvailability = includeAvailability == true;
  }

  global void execute(SchedulableContext context) {
    if (configDeveloperNames == null || configDeveloperNames.isEmpty()) {
      return;
    }

    if (Test.isRunningTest() && skipQueueableExecutionInTests) {
      lastExecutedConfigDeveloperNames = new List<String>(configDeveloperNames);
      lastExecutedSyncMode = syncMode;
      lastExecutedRunProducts = runProducts;
      lastExecutedIncludeAvailability = includeAvailability;
      return;
    }

    System.enqueueJob(
      new CatalogSyncChainQueueable(
        configDeveloperNames,
        syncMode,
        runProducts,
        includeAvailability
      )
    );
  }

  public static String scheduleChainedSync(
    List<String> configDeveloperNames,
    String syncMode,
    Boolean includeAvailability,
    String cronExpression
  ) {
    return scheduleChainedSync(
      null,
      configDeveloperNames,
      syncMode,
      true,
      includeAvailability,
      cronExpression
    );
  }

  public static String upsertChainedSync(
    String chainName,
    List<String> configDeveloperNames,
    String syncMode,
    Boolean runProducts,
    Boolean includeAvailability,
    String cronExpression
  ) {
    String baseJobName = buildScheduledJobName(chainName, syncMode);
    clearChainedSchedule(baseJobName);
    return scheduleChainedSync(
      chainName,
      configDeveloperNames,
      syncMode,
      runProducts,
      includeAvailability,
      cronExpression
    );
  }

  public static String scheduleChainedSync(
    String chainName,
    List<String> configDeveloperNames,
    String syncMode,
    Boolean runProducts,
    Boolean includeAvailability,
    String cronExpression
  ) {
    List<String> normalizedConfigNames = CatalogSyncChainQueueable.normalizeConfigDeveloperNames(
      configDeveloperNames
    );
    if (normalizedConfigNames.isEmpty()) {
      throw new CatalogJobConfigException(
        'At least one Catalog Job Config is required for a chained schedule.'
      );
    }
    if (String.isBlank(cronExpression)) {
      throw new CatalogJobConfigException(
        'A cron expression is required for a chained schedule.'
      );
    }

    String resolvedSyncMode = String.isBlank(syncMode)
      ? null
      : CatalogSyncMode.resolve(syncMode);
    String baseJobName = buildScheduledJobName(chainName, resolvedSyncMode);
    CatalogChainedSyncScheduler scheduler = new CatalogChainedSyncScheduler(
      chainName,
      normalizedConfigNames,
      resolvedSyncMode,
      runProducts,
      includeAvailability
    );
    List<Integer> minuteValues = parseMinuteCadenceValues(cronExpression);
    if (minuteValues.size() > 4) {
      throw new CatalogJobConfigException(
        'Minute chained schedules currently support up to four runs per hour.'
      );
    }

    if (minuteValues.isEmpty()) {
      return System.schedule(baseJobName, cronExpression, scheduler);
    }

    String firstJobId;
    for (Integer minuteValue : minuteValues) {
      String jobId = System.schedule(
        baseJobName + MINUTE_JOB_NAME_SEPARATOR + minuteValue + ']',
        '0 ' + minuteValue + ' * * * ?',
        scheduler
      );
      if (firstJobId == null) {
        firstJobId = jobId;
      }
    }
    return firstJobId;
  }

  public static void clearChainedSchedule(String jobNamePrefix) {
    if (String.isBlank(jobNamePrefix)) {
      return;
    }

    String normalizedPrefix = jobNamePrefix.trim();
    String queryPattern = normalizedPrefix + '%';
    for (CronTrigger scheduledTrigger : [
      SELECT Id, State, CronJobDetail.Name
      FROM CronTrigger
      WHERE CronJobDetail.Name LIKE :queryPattern
    ]) {
      String jobName = scheduledTrigger.CronJobDetail.Name;
      if (
        !TERMINAL_JOB_STATES.contains(scheduledTrigger.State) &&
        (jobName == normalizedPrefix ||
        jobName.startsWith(normalizedPrefix + MINUTE_JOB_NAME_SEPARATOR))
      ) {
        System.abortJob(scheduledTrigger.Id);
      }
    }
  }

  public static String buildScheduledJobName(
    String chainName,
    String syncMode
  ) {
    String normalizedName = normalizeChainName(chainName);
    String modeLabel = String.isBlank(syncMode)
      ? 'Mixed'
      : CatalogSyncMode.resolve(syncMode);
    return JOB_NAME_PREFIX + ' [' + modeLabel + '] ' + normalizedName;
  }

  private static String normalizeChainName(String chainName) {
    String normalizedName = String.isBlank(chainName)
      ? 'Shared Catalog'
      : chainName.trim();
    if (normalizedName.length() <= 35) {
      return normalizedName;
    }

    String hashSuffix = EncodingUtil.convertToHex(
        Crypto.generateDigest('SHA-256', Blob.valueOf(normalizedName))
      )
      .substring(0, 8);
    return normalizedName.substring(0, 26) + '-' + hashSuffix;
  }

  private static List<Integer> parseMinuteCadenceValues(String cronExpression) {
    if (String.isBlank(cronExpression)) {
      return new List<Integer>();
    }
    List<String> cronTokens = cronExpression.trim().split('\\s+');
    if (
      cronTokens.size() < 6 ||
      cronTokens[0] != '0' ||
      cronTokens[2] != '*' ||
      cronTokens[3] != '*' ||
      cronTokens[4] != '*' ||
      cronTokens[5] != '?' ||
      !cronTokens[1].contains(',')
    ) {
      return new List<Integer>();
    }

    List<Integer> minuteValues = new List<Integer>();
    for (String rawMinute : cronTokens[1].split(',')) {
      try {
        Integer minuteValue = Integer.valueOf(rawMinute);
        if (minuteValue < 0 || minuteValue > 59) {
          return new List<Integer>();
        }
        minuteValues.add(minuteValue);
      } catch (Exception e) {
        return new List<Integer>();
      }
    }
    return minuteValues;
  }
}
