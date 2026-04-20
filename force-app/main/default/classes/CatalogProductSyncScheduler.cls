global with sharing class CatalogProductSyncScheduler implements Schedulable {
  @TestVisible
  private static final String JOB_NAME_PREFIX = 'Catalog Product Sync';
  @TestVisible
  private static final String MINUTE_JOB_NAME_SEPARATOR = ' [Minute ';
  @TestVisible
  private static final Integer MAX_MINUTE_SCHEDULE_SHARDS = 4;
  @TestVisible
  private static final Set<String> TERMINAL_JOB_STATES = new Set<String>{
    'COMPLETE',
    'DELETED',
    'ERROR'
  };
  @TestVisible
  private static final Set<String> SUPPORTED_WEEKLY_DAYS = new Set<String>{
    'SUN',
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT'
  };
  @TestVisible
  private static CatalogJobConfig__mdt testJobConfigOverride;
  @TestVisible
  private static Boolean skipBatchExecutionInTests = false;
  @TestVisible
  private static String lastExecutedConfigDeveloperName;
  @TestVisible
  private static String lastExecutedSyncMode;

  private String jobConfigDeveloperName;
  private String expectedSyncMode;

  global CatalogProductSyncScheduler() {
  }

  public class ScheduleSnapshot {
    public Boolean isScheduled;
    public String syncMode;
    public String jobName;
    public String state;
    public String cronExpression;
    public Datetime nextFireTime;
    public Datetime previousFireTime;
    public Integer timesTriggered;
    public Boolean cadenceRecognized;
    public String cadenceType;
    public Integer intervalMinutes;
    public Integer intervalHours;
    public String dayOfWeek;
    public Integer hourOfDay;
    public Integer minuteOfHour;
  }

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
      DeltaProductCatalogExportBatch deltaBatch = new DeltaProductCatalogExportBatch(
        jobConfigDeveloperName
      );
      Id deltaJobId = Database.executeBatch(
        deltaBatch,
        deltaBatch.getBatchSize()
      );
      CatalogSyncStateService.recordStartedProductSync(
        config,
        CatalogSyncMode.DELTA,
        deltaJobId,
        System.now()
      );
      return;
    }

    ProductCatalogExportBatch fullBatch = new ProductCatalogExportBatch(
      jobConfigDeveloperName
    );
    Id fullJobId = Database.executeBatch(fullBatch, fullBatch.getBatchSize());
    CatalogSyncStateService.recordStartedProductSync(
      config,
      CatalogSyncMode.FULL,
      fullJobId,
      System.now()
    );
  }

  public static String scheduleFullSync(
    String jobConfigDeveloperName,
    String cronExpression
  ) {
    return scheduleSync(
      jobConfigDeveloperName,
      cronExpression,
      CatalogSyncMode.FULL
    );
  }

  public static String scheduleDeltaSync(
    String jobConfigDeveloperName,
    String cronExpression
  ) {
    return scheduleSync(
      jobConfigDeveloperName,
      cronExpression,
      CatalogSyncMode.DELTA
    );
  }

  public static String upsertConfiguredSyncSchedule(
    String jobConfigDeveloperName,
    String cronExpression
  ) {
    CatalogJobConfig__mdt config = loadJobConfig(jobConfigDeveloperName);
    String syncMode = CatalogSyncMode.resolve(config);

    clearScheduledSync(jobConfigDeveloperName);

    if (syncMode == CatalogSyncMode.DELTA) {
      return scheduleDeltaSync(jobConfigDeveloperName, cronExpression);
    }

    return scheduleFullSync(jobConfigDeveloperName, cronExpression);
  }

  public static void clearScheduledSync(String jobConfigDeveloperName) {
    if (String.isBlank(jobConfigDeveloperName)) {
      return;
    }

    abortScheduledJobsByBaseNames(
      buildAllScheduledJobNames(jobConfigDeveloperName)
    );
  }

  public static Map<String, ScheduleSnapshot> getScheduleSnapshotsByDeveloperName(
    List<CatalogJobConfig__mdt> configs
  ) {
    Map<String, ScheduleSnapshot> snapshotsByDeveloperName = new Map<String, ScheduleSnapshot>();

    if (configs == null || configs.isEmpty()) {
      return snapshotsByDeveloperName;
    }

    Map<String, String> scheduleNameByDeveloperName = new Map<String, String>();

    for (CatalogJobConfig__mdt config : configs) {
      String syncMode = CatalogSyncMode.resolve(config);
      String scheduleName = buildScheduledJobName(
        config.DeveloperName,
        syncMode
      );
      scheduleNameByDeveloperName.put(config.DeveloperName, scheduleName);
    }

    Map<String, List<CronTrigger>> triggersByBaseName = loadActiveTriggersByBaseName(
      new Set<String>(scheduleNameByDeveloperName.values())
    );

    for (CatalogJobConfig__mdt config : configs) {
      String syncMode = CatalogSyncMode.resolve(config);
      String scheduleName = scheduleNameByDeveloperName.get(
        config.DeveloperName
      );
      snapshotsByDeveloperName.put(
        config.DeveloperName,
        buildScheduleSnapshot(
          syncMode,
          scheduleName,
          triggersByBaseName.get(scheduleName)
        )
      );
    }

    return snapshotsByDeveloperName;
  }

  public static ScheduleSnapshot getConfiguredScheduleSnapshot(
    String jobConfigDeveloperName
  ) {
    CatalogJobConfig__mdt config = loadJobConfig(jobConfigDeveloperName);

    return getScheduleSnapshotsByDeveloperName(
        new List<CatalogJobConfig__mdt>{ config }
      )
      .get(jobConfigDeveloperName);
  }

  public static String buildMinuteCronExpression(
    Integer intervalMinutes,
    Integer startMinuteOfHour
  ) {
    if (
      intervalMinutes == null ||
      intervalMinutes < 1 ||
      intervalMinutes > 59
    ) {
      throw new CatalogJobConfigException(
        'Minute schedules require an interval between 1 and 59 minutes.'
      );
    }
    if (Math.mod(60, intervalMinutes) != 0) {
      throw new CatalogJobConfigException(
        'Minute schedules require an interval that evenly divides 60.'
      );
    }
    if ((60 / intervalMinutes) > MAX_MINUTE_SCHEDULE_SHARDS) {
      throw new CatalogJobConfigException(
        'Minute schedules currently support up to four runs per hour.'
      );
    }
    if (
      startMinuteOfHour == null ||
      startMinuteOfHour < 0 ||
      startMinuteOfHour > 59
    ) {
      throw new CatalogJobConfigException(
        'Minute schedules require a starting minute between 0 and 59.'
      );
    }

    Integer normalizedStartMinute = Math.mod(
      startMinuteOfHour,
      intervalMinutes
    );
    List<String> minuteValues = new List<String>();

    for (
      Integer minuteValue = normalizedStartMinute;
      minuteValue < 60;
      minuteValue += intervalMinutes
    ) {
      minuteValues.add(String.valueOf(minuteValue));
    }

    return '0 ' + String.join(minuteValues, ',') + ' * * * ?';
  }

  public static String buildHourlyCronExpression(
    Integer intervalHours,
    Integer minuteOfHour
  ) {
    if (intervalHours == null || intervalHours < 1 || intervalHours > 24) {
      throw new CatalogJobConfigException(
        'Hourly schedules require an interval between 1 and 24 hours.'
      );
    }
    if (minuteOfHour == null || minuteOfHour < 0 || minuteOfHour > 59) {
      throw new CatalogJobConfigException(
        'Hourly schedules require a minute value between 0 and 59.'
      );
    }

    return '0 ' + minuteOfHour + ' 0/' + intervalHours + ' * * ?';
  }

  public static String buildWeeklyCronExpression(
    String dayOfWeek,
    Integer hourOfDay,
    Integer minuteOfHour
  ) {
    String normalizedDay = String.isBlank(dayOfWeek)
      ? null
      : dayOfWeek.trim().toUpperCase();

    if (!SUPPORTED_WEEKLY_DAYS.contains(normalizedDay)) {
      throw new CatalogJobConfigException(
        'Weekly schedules require a valid day of week.'
      );
    }
    if (hourOfDay == null || hourOfDay < 0 || hourOfDay > 23) {
      throw new CatalogJobConfigException(
        'Weekly schedules require an hour value between 0 and 23.'
      );
    }
    if (minuteOfHour == null || minuteOfHour < 0 || minuteOfHour > 59) {
      throw new CatalogJobConfigException(
        'Weekly schedules require a minute value between 0 and 59.'
      );
    }

    return '0 ' + minuteOfHour + ' ' + hourOfDay + ' ? * ' + normalizedDay;
  }

  private static String scheduleSync(
    String jobConfigDeveloperName,
    String cronExpression,
    String syncMode
  ) {
    List<Integer> minuteValues = parseMinuteCadenceValues(cronExpression);

    if (minuteValues.isEmpty()) {
      return System.schedule(
        buildScheduledJobName(jobConfigDeveloperName, syncMode),
        cronExpression,
        new CatalogProductSyncScheduler(jobConfigDeveloperName, syncMode)
      );
    }

    String firstJobId;
    for (Integer minuteValue : minuteValues) {
      String jobId = System.schedule(
        buildMinuteScheduledJobName(
          jobConfigDeveloperName,
          syncMode,
          minuteValue
        ),
        buildMinuteShardCronExpression(minuteValue),
        new CatalogProductSyncScheduler(jobConfigDeveloperName, syncMode)
      );
      if (firstJobId == null) {
        firstJobId = jobId;
      }
    }

    return firstJobId;
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
  private static String buildMinuteScheduledJobName(
    String jobConfigDeveloperName,
    String syncMode,
    Integer minuteOfHour
  ) {
    return buildScheduledJobName(jobConfigDeveloperName, syncMode) +
      MINUTE_JOB_NAME_SEPARATOR +
      String.valueOf(minuteOfHour) +
      ']';
  }

  private static String buildMinuteShardCronExpression(Integer minuteOfHour) {
    return '0 ' + minuteOfHour + ' * * * ?';
  }

  @TestVisible
  private static CatalogJobConfig__mdt loadJobConfig(String developerName) {
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

  private static ScheduleSnapshot buildScheduleSnapshot(
    String syncMode,
    String scheduleName,
    List<CronTrigger> jobTriggers
  ) {
    ScheduleSnapshot snapshot = new ScheduleSnapshot();
    snapshot.syncMode = CatalogSyncMode.resolve(syncMode);
    snapshot.jobName = scheduleName;
    snapshot.isScheduled = jobTriggers != null && !jobTriggers.isEmpty();
    snapshot.cadenceRecognized = false;

    if (jobTriggers == null || jobTriggers.isEmpty()) {
      return snapshot;
    }

    applyTriggerSummary(snapshot, jobTriggers);
    applyKnownCadence(snapshot, jobTriggers);

    return snapshot;
  }

  private static void applyKnownCadence(
    ScheduleSnapshot snapshot,
    List<CronTrigger> jobTriggers
  ) {
    if (jobTriggers == null || jobTriggers.isEmpty()) {
      return;
    }

    if (
      jobTriggers.size() > 1 &&
      applyMinuteCadenceFromTriggers(snapshot, jobTriggers)
    ) {
      return;
    }

    String cronExpression = jobTriggers[0].CronExpression;
    if (String.isBlank(cronExpression)) {
      return;
    }

    List<String> cronTokens = cronExpression.trim().split('\\s+');

    if (
      cronTokens.size() >= 6 &&
      cronTokens[0] == '0' &&
      cronTokens[2] == '*' &&
      cronTokens[3] == '*' &&
      cronTokens[4] == '*' &&
      cronTokens[5] == '?' &&
      cronTokens[1] != null &&
      cronTokens[1].contains(',')
    ) {
      List<Integer> minuteValues = new List<Integer>();

      for (String rawMinuteValue : cronTokens[1].split(',')) {
        Integer minuteValue = tryParseInteger(rawMinuteValue);
        if (minuteValue == null || minuteValue < 0 || minuteValue > 59) {
          minuteValues.clear();
          break;
        }
        minuteValues.add(minuteValue);
      }

      Integer intervalMinutes = inferMinuteCadence(minuteValues);

      if (!minuteValues.isEmpty() && intervalMinutes != null) {
        snapshot.cadenceRecognized = true;
        snapshot.cadenceType = 'Minutes';
        snapshot.intervalMinutes = intervalMinutes;
        snapshot.minuteOfHour = minuteValues[0];
        return;
      }
    }

    if (
      cronTokens.size() >= 6 &&
      cronTokens[0] == '0' &&
      cronTokens[3] == '*' &&
      cronTokens[4] == '*' &&
      cronTokens[5] == '?' &&
      cronTokens[2] != null &&
      cronTokens[2].startsWith('0/')
    ) {
      Integer intervalHours = tryParseInteger(cronTokens[2].substring(2));
      Integer minuteOfHour = tryParseInteger(cronTokens[1]);

      if (intervalHours != null && minuteOfHour != null) {
        snapshot.cadenceRecognized = true;
        snapshot.cadenceType = 'Hourly';
        snapshot.intervalHours = intervalHours;
        snapshot.minuteOfHour = minuteOfHour;
        return;
      }
    }

    if (
      cronTokens.size() >= 6 &&
      cronTokens[0] == '0' &&
      cronTokens[3] == '?' &&
      cronTokens[4] == '*'
    ) {
      Integer minuteOfHour = tryParseInteger(cronTokens[1]);
      Integer hourOfDay = tryParseInteger(cronTokens[2]);
      String dayOfWeek = cronTokens[5];

      if (
        minuteOfHour != null &&
        hourOfDay != null &&
        SUPPORTED_WEEKLY_DAYS.contains(dayOfWeek)
      ) {
        snapshot.cadenceRecognized = true;
        snapshot.cadenceType = 'Weekly';
        snapshot.minuteOfHour = minuteOfHour;
        snapshot.hourOfDay = hourOfDay;
        snapshot.dayOfWeek = dayOfWeek;
      }
    }
  }

  private static void applyTriggerSummary(
    ScheduleSnapshot snapshot,
    List<CronTrigger> jobTriggers
  ) {
    List<String> cronExpressions = new List<String>();
    Integer totalTimesTriggered = 0;

    for (CronTrigger jobTrigger : jobTriggers) {
      cronExpressions.add(jobTrigger.CronExpression);
      totalTimesTriggered += jobTrigger.TimesTriggered == null
        ? 0
        : jobTrigger.TimesTriggered;

      if (
        snapshot.state == null ||
        isHigherPriorityState(jobTrigger.State, snapshot.state)
      ) {
        snapshot.state = jobTrigger.State;
      }

      if (
        jobTrigger.NextFireTime != null &&
        (snapshot.nextFireTime == null ||
        jobTrigger.NextFireTime < snapshot.nextFireTime)
      ) {
        snapshot.nextFireTime = jobTrigger.NextFireTime;
      }

      if (
        jobTrigger.PreviousFireTime != null &&
        (snapshot.previousFireTime == null ||
        jobTrigger.PreviousFireTime > snapshot.previousFireTime)
      ) {
        snapshot.previousFireTime = jobTrigger.PreviousFireTime;
      }
    }

    snapshot.cronExpression = String.join(cronExpressions, ' | ');
    snapshot.timesTriggered = totalTimesTriggered;
  }

  private static Boolean applyMinuteCadenceFromTriggers(
    ScheduleSnapshot snapshot,
    List<CronTrigger> jobTriggers
  ) {
    List<Integer> minuteValues = new List<Integer>();

    for (CronTrigger jobTrigger : jobTriggers) {
      List<String> cronTokens = String.isBlank(jobTrigger.CronExpression)
        ? new List<String>()
        : jobTrigger.CronExpression.trim().split('\\s+');

      if (
        cronTokens.size() < 6 ||
        cronTokens[0] != '0' ||
        cronTokens[2] != '*' ||
        cronTokens[3] != '*' ||
        cronTokens[4] != '*' ||
        cronTokens[5] != '?'
      ) {
        return false;
      }

      Integer minuteValue = tryParseInteger(cronTokens[1]);
      if (minuteValue == null || minuteValue < 0 || minuteValue > 59) {
        return false;
      }

      minuteValues.add(minuteValue);
    }

    minuteValues.sort();
    Integer intervalMinutes = inferMinuteCadence(minuteValues);
    if (intervalMinutes == null) {
      return false;
    }

    snapshot.cadenceRecognized = true;
    snapshot.cadenceType = 'Minutes';
    snapshot.intervalMinutes = intervalMinutes;
    snapshot.minuteOfHour = minuteValues[0];
    return true;
  }

  private static Boolean isHigherPriorityState(
    String candidateState,
    String currentState
  ) {
    return getStatePriority(candidateState) > getStatePriority(currentState);
  }

  private static Integer getStatePriority(String state) {
    switch on state {
      when 'EXECUTING' {
        return 5;
      }
      when 'ACQUIRED' {
        return 4;
      }
      when 'WAITING' {
        return 3;
      }
      when 'BLOCKED' {
        return 2;
      }
      when 'PAUSED' {
        return 1;
      }
      when 'PAUSED_BLOCKED' {
        return 1;
      }
      when else {
        return 0;
      }
    }
  }

  private static Integer tryParseInteger(String rawValue) {
    if (String.isBlank(rawValue)) {
      return null;
    }

    try {
      return Integer.valueOf(rawValue);
    } catch (Exception e) {
      return null;
    }
  }

  private static Integer inferMinuteCadence(List<Integer> minuteValues) {
    if (minuteValues == null || minuteValues.size() < 2) {
      return null;
    }

    Integer inferredInterval = null;

    for (Integer index = 0; index < minuteValues.size(); index++) {
      Integer currentMinute = minuteValues[index];
      Integer nextMinute = index == minuteValues.size() - 1
        ? minuteValues[0] + 60
        : minuteValues[index + 1];
      Integer gap = nextMinute - currentMinute;

      if (gap <= 0) {
        return null;
      }

      if (inferredInterval == null) {
        inferredInterval = gap;
      } else if (inferredInterval != gap) {
        return null;
      }
    }

    return inferredInterval;
  }

  private static Set<String> buildAllScheduledJobNames(
    String jobConfigDeveloperName
  ) {
    return new Set<String>{
      buildScheduledJobName(jobConfigDeveloperName, CatalogSyncMode.FULL),
      buildScheduledJobName(jobConfigDeveloperName, CatalogSyncMode.DELTA)
    };
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
      !String.valueOf(cronTokens[1]).contains(',')
    ) {
      return new List<Integer>();
    }

    List<Integer> minuteValues = new List<Integer>();
    for (String rawMinuteValue : cronTokens[1].split(',')) {
      Integer minuteValue = tryParseInteger(rawMinuteValue);
      if (minuteValue == null || minuteValue < 0 || minuteValue > 59) {
        return new List<Integer>();
      }
      minuteValues.add(minuteValue);
    }

    return minuteValues;
  }

  private static void abortScheduledJobsByBaseNames(Set<String> baseJobNames) {
    if (baseJobNames == null || baseJobNames.isEmpty()) {
      return;
    }

    Map<String, List<CronTrigger>> triggersByBaseName = loadActiveTriggersByBaseName(
      baseJobNames
    );

    for (List<CronTrigger> groupedTriggers : triggersByBaseName.values()) {
      for (CronTrigger jobTrigger : groupedTriggers) {
        if (!TERMINAL_JOB_STATES.contains(jobTrigger.State)) {
          System.abortJob(jobTrigger.Id);
        }
      }
    }
  }

  private static String resolveBaseScheduledJobName(String jobName) {
    if (String.isBlank(jobName)) {
      return jobName;
    }

    Integer separatorIndex = jobName.indexOf(MINUTE_JOB_NAME_SEPARATOR);
    return separatorIndex > 0 ? jobName.substring(0, separatorIndex) : jobName;
  }

  private static Map<String, List<CronTrigger>> loadActiveTriggersByBaseName(
    Set<String> baseJobNames
  ) {
    Map<String, List<CronTrigger>> triggersByBaseName = new Map<String, List<CronTrigger>>();
    String jobNamePattern = JOB_NAME_PREFIX + '%';

    if (baseJobNames == null || baseJobNames.isEmpty()) {
      return triggersByBaseName;
    }

    for (CronTrigger jobTrigger : [
      SELECT
        Id,
        CronExpression,
        State,
        NextFireTime,
        PreviousFireTime,
        TimesTriggered,
        CreatedDate,
        CronJobDetail.Name
      FROM CronTrigger
      WHERE CronJobDetail.Name LIKE :jobNamePattern
      ORDER BY CreatedDate DESC
    ]) {
      String baseJobName = resolveBaseScheduledJobName(
        jobTrigger.CronJobDetail.Name
      );

      if (!TERMINAL_JOB_STATES.contains(jobTrigger.State)) {
        if (!baseJobNames.contains(baseJobName)) {
          continue;
        }

        if (!triggersByBaseName.containsKey(baseJobName)) {
          triggersByBaseName.put(baseJobName, new List<CronTrigger>());
        }

        triggersByBaseName.get(baseJobName).add(jobTrigger);
      }
    }

    return triggersByBaseName;
  }
}
