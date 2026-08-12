@IsTest
private class CatalogChainedSyncSchedulerTest {
  @TestSetup
  static void clearTestState() {
    CatalogSyncChainQueueable.skipLaunchInTests = false;
    CatalogChainedSyncScheduler.skipQueueableExecutionInTests = false;
  }

  @IsTest
  static void queueableNormalizesAndProcessesOneConfigPerTransaction() {
    CatalogSyncChainQueueable.skipLaunchInTests = true;
    CatalogSyncChainQueueable queueable = new CatalogSyncChainQueueable(
      new List<String>{ ' FIRST ', 'SECOND', 'FIRST', null },
      CatalogSyncMode.FULL,
      true,
      true
    );

    queueable.execute(null);

    System.assertEquals(
      'FIRST',
      CatalogSyncChainQueueable.lastProcessedConfigDeveloperName
    );
    System.assertEquals(
      CatalogSyncMode.FULL,
      CatalogSyncChainQueueable.lastExpectedSyncMode
    );
    System.assertEquals(true, CatalogSyncChainQueueable.lastRunProducts);
    System.assertEquals(
      true,
      CatalogSyncChainQueueable.lastIncludeAvailability
    );
    System.assertEquals(
      new List<String>{ 'SECOND' },
      CatalogSyncChainQueueable.lastRemainingConfigDeveloperNames
    );
  }

  @IsTest
  static void schedulerExecuteEnqueuesConfiguredChain() {
    CatalogChainedSyncScheduler.skipQueueableExecutionInTests = true;
    CatalogChainedSyncScheduler scheduler = new CatalogChainedSyncScheduler(
      'Shared Stores',
      new List<String>{ 'FULL_A', 'FULL_B' },
      CatalogSyncMode.FULL,
      true,
      true
    );

    scheduler.execute(null);

    System.assertEquals(
      new List<String>{ 'FULL_A', 'FULL_B' },
      CatalogChainedSyncScheduler.lastExecutedConfigDeveloperNames
    );
    System.assertEquals(
      CatalogSyncMode.FULL,
      CatalogChainedSyncScheduler.lastExecutedSyncMode
    );
    System.assertEquals(
      true,
      CatalogChainedSyncScheduler.lastExecutedIncludeAvailability
    );
  }

  @IsTest
  static void schedulesAndClearsSingleHourlyChain() {
    CatalogChainedSyncScheduler.skipQueueableExecutionInTests = true;
    String jobId = CatalogChainedSyncScheduler.scheduleChainedSync(
      'Shared Stores',
      new List<String>{ 'FULL_A', 'FULL_B' },
      CatalogSyncMode.FULL,
      true,
      false,
      '0 15 0/2 * * ?'
    );
    Id scheduledJobId = (Id) jobId;

    CronTrigger scheduledTrigger = [
      SELECT CronExpression, CronJobDetail.Name
      FROM CronTrigger
      WHERE Id = :scheduledJobId
    ];
    System.assertEquals('0 15 0/2 * * ?', scheduledTrigger.CronExpression);
    System.assertEquals(
      'Catalog Chained Sync [Full] Shared Stores',
      scheduledTrigger.CronJobDetail.Name
    );

    CatalogChainedSyncScheduler.clearChainedSchedule(
      'Catalog Chained Sync [Full] Shared Stores'
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE
          Id = :scheduledJobId
          AND State NOT IN ('DELETED', 'COMPLETE', 'ERROR')
      ]
    );
  }

  @IsTest
  static void minuteCadenceUsesFixedNumberOfSharedShards() {
    CatalogChainedSyncScheduler.skipQueueableExecutionInTests = true;
    CatalogChainedSyncScheduler.scheduleChainedSync(
      'Delta Stores',
      new List<String>{ 'DELTA_A', 'DELTA_B', 'DELTA_C' },
      CatalogSyncMode.DELTA,
      false,
      false,
      '0 5,20,35,50 * * * ?'
    );

    List<CronTrigger> triggers = [
      SELECT Id
      FROM CronTrigger
      WHERE CronJobDetail.Name LIKE 'Catalog Chained Sync [Delta] Delta Stores%'
    ];
    System.assertEquals(
      4,
      triggers.size(),
      'The cadence should use four shared jobs, not one job per config.'
    );

    CatalogChainedSyncScheduler.clearChainedSchedule(
      'Catalog Chained Sync [Delta] Delta Stores'
    );
  }

  @IsTest
  static void longChainNamesRetainDeterministicUniqueness() {
    String commonPrefix = 'A shared catalog chain name with common prefix ';
    String firstJobName = CatalogChainedSyncScheduler.buildScheduledJobName(
      commonPrefix + 'A',
      CatalogSyncMode.FULL
    );
    String secondJobName = CatalogChainedSyncScheduler.buildScheduledJobName(
      commonPrefix + 'B',
      CatalogSyncMode.FULL
    );

    System.assertNotEquals(firstJobName, secondJobName);
    System.assert(firstJobName.length() <= 63);
    System.assertEquals(
      firstJobName,
      CatalogChainedSyncScheduler.buildScheduledJobName(
        commonPrefix + 'A',
        CatalogSyncMode.FULL
      )
    );
  }
}
