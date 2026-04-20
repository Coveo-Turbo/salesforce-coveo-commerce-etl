@IsTest
private class CatalogProductSyncSchedulerTest {
  @TestSetup
  static void clearSchedulerOverride() {
    CatalogProductSyncScheduler.testJobConfigOverride = null;
    CatalogProductSyncScheduler.skipBatchExecutionInTests = false;
    CatalogProductSyncScheduler.lastExecutedConfigDeveloperName = null;
    CatalogProductSyncScheduler.lastExecutedSyncMode = null;
  }

  @IsTest
  static void testBuildScheduledJobName_includesModeAndConfig() {
    System.assertEquals(
      'Catalog Product Sync [Full] FULL_CONFIG',
      CatalogProductSyncScheduler.buildScheduledJobName(
        'FULL_CONFIG',
        CatalogSyncMode.FULL
      )
    );
    System.assertEquals(
      'Catalog Product Sync [Delta] DELTA_CONFIG',
      CatalogProductSyncScheduler.buildScheduledJobName(
        'DELTA_CONFIG',
        CatalogSyncMode.DELTA
      )
    );
  }

  @IsTest
  static void testScheduleHelpers_createCronTriggers() {
    CatalogProductSyncScheduler.skipBatchExecutionInTests = true;
    String fullJobId = CatalogProductSyncScheduler.scheduleFullSync(
      'FULL_CONFIG',
      '0 0 0 1 1 ? 2099'
    );
    String deltaJobId = CatalogProductSyncScheduler.scheduleDeltaSync(
      'DELTA_CONFIG',
      '0 0 1 1 1 ? 2099'
    );

    Map<Id, CronTrigger> triggersById = new Map<Id, CronTrigger>(
      [
        SELECT Id, CronJobDetail.Name
        FROM CronTrigger
        WHERE Id IN :new Set<Id>{ (Id) fullJobId, (Id) deltaJobId }
      ]
    );

    System.assertEquals(
      'Catalog Product Sync [Full] FULL_CONFIG',
      triggersById.get((Id) fullJobId).CronJobDetail.Name
    );
    System.assertEquals(
      'Catalog Product Sync [Delta] DELTA_CONFIG',
      triggersById.get((Id) deltaJobId).CronJobDetail.Name
    );

    System.abortJob(fullJobId);
    System.abortJob(deltaJobId);
  }

  @IsTest
  static void testExecute_rejectsSyncModeMismatch() {
    CatalogProductSyncScheduler.testJobConfigOverride = new CatalogJobConfig__mdt(
      DeveloperName = 'DELTA_CONFIG',
      MasterLabel = 'Delta Config',
      SyncMode__c = CatalogSyncMode.DELTA
    );

    Boolean exceptionThrown = false;

    try {
      new CatalogProductSyncScheduler('DELTA_CONFIG', CatalogSyncMode.FULL)
        .execute(null);
    } catch (CatalogJobConfigException e) {
      exceptionThrown = true;
      System.assert(e.getMessage().contains('expected SyncMode__c = Full'));
    }

    System.assertEquals(true, exceptionThrown);
  }

  @IsTest
  static void testExecute_returnsEarlyWhenConfigNameIsBlank() {
    Test.startTest();
    new CatalogProductSyncScheduler(null, CatalogSyncMode.FULL).execute(null);
    Test.stopTest();

    System.assertEquals(
      null,
      CatalogProductSyncScheduler.lastExecutedConfigDeveloperName
    );
  }

  @IsTest
  static void testExecute_capturesFullModeWhenBatchExecutionIsSkipped() {
    CatalogProductSyncScheduler.skipBatchExecutionInTests = true;
    CatalogProductSyncScheduler.testJobConfigOverride = new CatalogJobConfig__mdt(
      DeveloperName = 'FULL_CONFIG',
      MasterLabel = 'Full Config',
      SyncMode__c = CatalogSyncMode.FULL
    );

    new CatalogProductSyncScheduler('FULL_CONFIG', CatalogSyncMode.FULL)
      .execute(null);

    System.assertEquals(
      'FULL_CONFIG',
      CatalogProductSyncScheduler.lastExecutedConfigDeveloperName
    );
    System.assertEquals(
      CatalogSyncMode.FULL,
      CatalogProductSyncScheduler.lastExecutedSyncMode
    );
  }

  @IsTest
  static void testExecute_capturesDeltaModeWhenBatchExecutionIsSkipped() {
    CatalogProductSyncScheduler.skipBatchExecutionInTests = true;
    CatalogProductSyncScheduler.testJobConfigOverride = new CatalogJobConfig__mdt(
      DeveloperName = 'DELTA_CONFIG',
      MasterLabel = 'Delta Config',
      SyncMode__c = CatalogSyncMode.DELTA
    );

    new CatalogProductSyncScheduler('DELTA_CONFIG', CatalogSyncMode.DELTA)
      .execute(null);

    System.assertEquals(
      'DELTA_CONFIG',
      CatalogProductSyncScheduler.lastExecutedConfigDeveloperName
    );
    System.assertEquals(
      CatalogSyncMode.DELTA,
      CatalogProductSyncScheduler.lastExecutedSyncMode
    );
  }

  @IsTest
  static void testBuildCronExpressionHelpers_formatSupportedCadences() {
    System.assertEquals(
      '0 5,20,35,50 * * * ?',
      CatalogProductSyncScheduler.buildMinuteCronExpression(15, 5)
    );
    System.assertEquals(
      '0 15 0/2 * * ?',
      CatalogProductSyncScheduler.buildHourlyCronExpression(2, 15)
    );
    System.assertEquals(
      '0 30 4 ? * SUN',
      CatalogProductSyncScheduler.buildWeeklyCronExpression('sun', 4, 30)
    );
  }

  @IsTest
  static void testBuildMinuteCronExpression_rejectsNonDivisorOfSixty() {
    Boolean exceptionThrown = false;

    try {
      CatalogProductSyncScheduler.buildMinuteCronExpression(17, 0);
    } catch (CatalogJobConfigException e) {
      exceptionThrown = true;
      System.assert(
        e.getMessage().contains('evenly divides 60'),
        'Expected divisor validation message.'
      );
    }

    System.assertEquals(true, exceptionThrown);
  }

  @IsTest
  static void testGetScheduleSnapshotsByDeveloperName_parsesHourlyCadence() {
    CatalogProductSyncScheduler.skipBatchExecutionInTests = true;
    String jobId = CatalogProductSyncScheduler.scheduleFullSync(
      'FULL_CONFIG',
      '0 15 0/2 * * ?'
    );

    Map<String, CatalogProductSyncScheduler.ScheduleSnapshot> snapshotsByDeveloperName = CatalogProductSyncScheduler.getScheduleSnapshotsByDeveloperName(
      new List<CatalogJobConfig__mdt>{
        new CatalogJobConfig__mdt(
          DeveloperName = 'FULL_CONFIG',
          MasterLabel = 'Full Config',
          SyncMode__c = CatalogSyncMode.FULL
        )
      }
    );

    CatalogProductSyncScheduler.ScheduleSnapshot snapshot = snapshotsByDeveloperName.get(
      'FULL_CONFIG'
    );

    System.assertEquals(true, snapshot.isScheduled);
    System.assertEquals(
      'Catalog Product Sync [Full] FULL_CONFIG',
      snapshot.jobName
    );
    System.assertEquals(true, snapshot.cadenceRecognized);
    System.assertEquals('Hourly', snapshot.cadenceType);
    System.assertEquals(2, snapshot.intervalHours);
    System.assertEquals(15, snapshot.minuteOfHour);

    System.abortJob(jobId);
  }

  @IsTest
  static void testGetScheduleSnapshotsByDeveloperName_parsesMinuteCadence() {
    CatalogProductSyncScheduler.skipBatchExecutionInTests = true;
    CatalogProductSyncScheduler.scheduleDeltaSync(
      'DELTA_CONFIG',
      '0 5,20,35,50 * * * ?'
    );

    Map<String, CatalogProductSyncScheduler.ScheduleSnapshot> snapshotsByDeveloperName = CatalogProductSyncScheduler.getScheduleSnapshotsByDeveloperName(
      new List<CatalogJobConfig__mdt>{
        new CatalogJobConfig__mdt(
          DeveloperName = 'DELTA_CONFIG',
          MasterLabel = 'Delta Config',
          SyncMode__c = CatalogSyncMode.DELTA
        )
      }
    );

    CatalogProductSyncScheduler.ScheduleSnapshot snapshot = snapshotsByDeveloperName.get(
      'DELTA_CONFIG'
    );

    System.assertEquals(true, snapshot.isScheduled);
    System.assertEquals(
      'Catalog Product Sync [Delta] DELTA_CONFIG',
      snapshot.jobName
    );
    System.assertEquals(true, snapshot.cadenceRecognized);
    System.assertEquals('Minutes', snapshot.cadenceType);
    System.assertEquals(15, snapshot.intervalMinutes);
    System.assertEquals(5, snapshot.minuteOfHour);

    CatalogProductSyncScheduler.clearScheduledSync('DELTA_CONFIG');
  }

  @IsTest
  static void testUpsertConfiguredSyncSchedule_replacesExistingJob() {
    CatalogProductSyncScheduler.skipBatchExecutionInTests = true;
    CatalogProductSyncScheduler.testJobConfigOverride = new CatalogJobConfig__mdt(
      DeveloperName = 'FULL_CONFIG',
      MasterLabel = 'Full Config',
      SyncMode__c = CatalogSyncMode.FULL
    );

    String originalJobId = CatalogProductSyncScheduler.scheduleFullSync(
      'FULL_CONFIG',
      '0 0 0 1 1 ? 2099'
    );
    String replacementJobId = CatalogProductSyncScheduler.upsertConfiguredSyncSchedule(
      'FULL_CONFIG',
      '0 30 0/4 * * ?'
    );

    Set<String> terminalStates = new Set<String>{
      'DELETED',
      'COMPLETE',
      'ERROR'
    };
    List<CronTrigger> activeTriggers = [
      SELECT Id, CronExpression, State, CronJobDetail.Name
      FROM CronTrigger
      WHERE
        CronJobDetail.Name = 'Catalog Product Sync [Full] FULL_CONFIG'
        AND State NOT IN :terminalStates
    ];

    System.assertNotEquals(originalJobId, replacementJobId);
    System.assertEquals(1, activeTriggers.size());
    System.assertEquals('0 30 0/4 * * ?', activeTriggers[0].CronExpression);
  }

  @IsTest
  static void testClearScheduledSync_abortsFullAndDeltaJobs() {
    CatalogProductSyncScheduler.skipBatchExecutionInTests = true;
    String fullJobId = CatalogProductSyncScheduler.scheduleFullSync(
      'PAIR_CONFIG',
      '0 0 0 1 1 ? 2099'
    );
    String deltaJobId = CatalogProductSyncScheduler.scheduleDeltaSync(
      'PAIR_CONFIG',
      '0 0 1 1 1 ? 2099'
    );

    CatalogProductSyncScheduler.clearScheduledSync('PAIR_CONFIG');

    Set<String> terminalStates = new Set<String>{
      'DELETED',
      'COMPLETE',
      'ERROR'
    };
    List<CronTrigger> activeTriggers = [
      SELECT Id, State
      FROM CronTrigger
      WHERE
        Id IN :new Set<Id>{ (Id) fullJobId, (Id) deltaJobId }
        AND State NOT IN :terminalStates
    ];

    System.assertEquals(0, activeTriggers.size());
  }
}
