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
    String fullJobId = CatalogProductSyncScheduler.scheduleFullSync(
      'FULL_CONFIG',
      '0 0 0 1 1 ? 2099'
    );
    String deltaJobId = CatalogProductSyncScheduler.scheduleDeltaSync(
      'DELTA_CONFIG',
      '0 0 1 1 1 ? 2099'
    );

    Map<Id, CronTrigger> triggersById = new Map<Id, CronTrigger>([
      SELECT Id, CronJobDetail.Name
      FROM CronTrigger
      WHERE Id IN :new Set<Id>{ (Id) fullJobId, (Id) deltaJobId }
    ]);

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
    CatalogProductSyncScheduler.testJobConfigOverride =
      new CatalogJobConfig__mdt(
        DeveloperName = 'DELTA_CONFIG',
        MasterLabel = 'Delta Config',
        SyncMode__c = CatalogSyncMode.DELTA
      );

    Boolean exceptionThrown = false;

    try {
      new CatalogProductSyncScheduler(
        'DELTA_CONFIG',
        CatalogSyncMode.FULL
      )
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
    CatalogProductSyncScheduler.testJobConfigOverride =
      new CatalogJobConfig__mdt(
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
    CatalogProductSyncScheduler.testJobConfigOverride =
      new CatalogJobConfig__mdt(
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
}
