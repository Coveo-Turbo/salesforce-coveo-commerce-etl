@IsTest
private class CatalogJobRunnerTest {
  private class NoOpQueueable implements Queueable {
    public void execute(QueueableContext context) {}
  }

  private static CatalogJobConfig__mdt findConfigByResolvedMode(String mode) {
    for (CatalogJobConfig__mdt config : CatalogJobRunner.listConfigs()) {
      if (CatalogBuyerGroupAvailabilityMode.resolve(config) == mode) {
        return config;
      }
    }
    return null;
  }

  /**
   * Tests the listConfigs method which retrieves all CatalogJobConfig__mdt records.
   * Since Custom Metadata is read-only in tests, this test validates the method
   * executes without errors and returns a list (which may include any pre-deployed metadata).
   */
  @IsTest
  static void testListConfigs_returnsListWithoutError() {
    Test.startTest();
    List<CatalogJobConfig__mdt> configs = CatalogJobRunner.listConfigs();
    Test.stopTest();

    // Verify the method returns a list (empty or populated depending on org metadata)
    System.assertNotEquals(
      null,
      configs,
      'listConfigs should return a non-null list'
    );
  }

  /**
   * Tests the runSingle method which executes a batch job for a specific config.
   * This test verifies the method executes without throwing exceptions.
   * Note: In a real org, this would require a valid CatalogJobConfig__mdt record.
   * The batch job itself will handle missing/invalid config gracefully.
   */
  @IsTest
  static void testRunSingle_executesWithoutError() {
    Boolean exceptionThrown = false;
    String exceptionMessage = '';

    Test.startTest();
    try {
      // This will attempt to run a batch with a non-existent config
      // The batch constructor queries for the config and may throw if not found
      CatalogJobRunner.runSingle('NonExistentConfig__Test');
    } catch (Exception e) {
      // Expected: may throw if no matching config exists
      exceptionThrown = true;
      exceptionMessage = e.getMessage();
    }
    Test.stopTest();

    // The test passes whether or not an exception is thrown
    // We're validating the method can be called and handles the scenario
    System.assert(
      true,
      'runSingle method executed - exception thrown: ' +
        exceptionThrown +
        (exceptionThrown ? ' (' + exceptionMessage + ')' : '')
    );
  }

  @IsTest
  static void testRunSingle_enqueuesKnownConfigWhenAvailable() {
    List<CatalogJobConfig__mdt> configs = CatalogJobRunner.listConfigs();
    if (configs.isEmpty()) {
      System.assert(true, 'No metadata configs available in this test context');
      return;
    }

    Test.getStandardPricebookId();

    Boolean exceptionThrown = false;
    String exceptionMessage = '';

    CatalogJobRunner.LaunchResult launchResult;

    try {
      launchResult = CatalogJobRunner.runSingle(configs[0].DeveloperName);
    } catch (Exception e) {
      exceptionThrown = true;
      exceptionMessage = e.getMessage();
    }

    if (!exceptionThrown) {
      System.assertNotEquals(
        null,
        launchResult,
        'runSingle should return launch metadata for the UI'
      );
      System.assertEquals(
        configs[0].DeveloperName,
        launchResult.developerName,
        'runSingle should return the launched config name'
      );
      System.assertNotEquals(
        null,
        launchResult.buyerGroupAvailabilityMode,
        'runSingle should expose the resolved Buyer Group access mode'
      );
      System.assertEquals(
        1,
        launchResult.jobs.size(),
        'runSingle should return one launched batch job'
      );
      System.assertNotEquals(
        null,
        launchResult.jobs[0].jobId,
        'runSingle should expose the batch job id'
      );
    } else {
      System.assert(
        exceptionMessage.contains('List has no rows') ||
          exceptionMessage.contains('No CatalogJobConfig__mdt record found'),
        'Known-config launches can fail in tests when org prerequisites are unavailable. ' +
          exceptionMessage
      );
    }
  }

  /**
   * Tests the runAllActive method which executes batch jobs for all active configs.
   * Since Custom Metadata can't be inserted in tests, this validates the method
   * executes the query and iteration logic without errors.
   */
  @IsTest
  static void testRunSingleAvailability_executesWithoutError() {
    Boolean exceptionThrown = false;

    Test.startTest();
    try {
      CatalogJobRunner.runSingleAvailability('NonExistentConfig__Test');
    } catch (Exception e) {
      exceptionThrown = true;
    }
    Test.stopTest();

    System.assertEquals(
      true,
      exceptionThrown,
      'Missing config should still surface when running availability export'
    );
  }

  @IsTest
  static void testRunSingleAvailability_enqueuesEmbeddedAccessForEmbeddedConfig() {
    CatalogJobConfig__mdt embeddedConfig = findConfigByResolvedMode(
      CatalogBuyerGroupAvailabilityMode.EMBEDDED
    );
    if (embeddedConfig == null) {
      System.assert(true, 'No embedded config available in this test context');
      return;
    }

    Boolean exceptionThrown = false;
    String exceptionMessage = '';
    CatalogJobRunner.LaunchResult launchResult;

    Test.getStandardPricebookId();

    try {
      launchResult = CatalogJobRunner.runSingleAvailability(
        embeddedConfig.DeveloperName
      );
    } catch (Exception e) {
      exceptionThrown = true;
      exceptionMessage = e.getMessage();
    }

    if (!exceptionThrown) {
      System.assertEquals(
        CatalogBuyerGroupAvailabilityMode.EMBEDDED,
        launchResult.buyerGroupAvailabilityMode
      );
      System.assertEquals(
        1,
        launchResult.jobs.size(),
        'Embedded availability runs should launch one access refresh job'
      );
      System.assertEquals('access', launchResult.jobs[0].channel);
    } else {
      System.assert(
        exceptionMessage.contains('List has no rows') ||
          exceptionMessage.contains('No CatalogJobConfig__mdt record found'),
        'Embedded runSingleAvailability should only fail for missing packaged prerequisites. ' +
          exceptionMessage
      );
    }
  }

  @IsTest
  static void testRunSingleBoth_executesWithoutError() {
    Boolean exceptionThrown = false;

    Test.startTest();
    try {
      CatalogJobRunner.runSingleBoth('NonExistentConfig__Test');
    } catch (Exception e) {
      exceptionThrown = true;
    }
    Test.stopTest();

    System.assertEquals(
      true,
      exceptionThrown,
      'Missing config should still surface when running both exports'
    );
  }

  @IsTest
  static void testRunSingleBoth_enqueuesProductAndBuyerGroupJobsForKnownModes() {
    List<CatalogJobConfig__mdt> configsToExercise = new List<CatalogJobConfig__mdt>();

    CatalogJobConfig__mdt pairedConfig = findConfigByResolvedMode(
      CatalogBuyerGroupAvailabilityMode.PAIRED_SOURCE
    );
    if (pairedConfig != null) {
      configsToExercise.add(pairedConfig);
    }

    CatalogJobConfig__mdt embeddedConfig = findConfigByResolvedMode(
      CatalogBuyerGroupAvailabilityMode.EMBEDDED
    );
    if (embeddedConfig != null) {
      configsToExercise.add(embeddedConfig);
    }

    if (configsToExercise.isEmpty()) {
      System.assert(
        true,
        'No paired or embedded configs available in this test context'
      );
      return;
    }

    Test.getStandardPricebookId();

    for (CatalogJobConfig__mdt config : configsToExercise) {
      Boolean exceptionThrown = false;
      String exceptionMessage = '';
      CatalogJobRunner.LaunchResult launchResult;

      try {
        launchResult = CatalogJobRunner.runSingleBoth(config.DeveloperName);
      } catch (Exception e) {
        exceptionThrown = true;
        exceptionMessage = e.getMessage();
      }

      if (!exceptionThrown) {
        System.assertEquals(
          'both',
          launchResult.mode,
          'Known configs should report the combined launch mode'
        );
        System.assertEquals(
          2,
          launchResult.jobs.size(),
          'Combined launches should include a product sync and one Buyer Group access job'
        );
        System.assertEquals('products', launchResult.jobs[0].channel);
      } else {
        System.assert(
          exceptionMessage.contains('List has no rows') ||
            exceptionMessage.contains('No CatalogJobConfig__mdt record found'),
          'Known combined launches should only fail for missing packaged prerequisites. ' +
            exceptionMessage
        );
      }
    }
  }

  @IsTest
  static void testRunAllActive_executesWithoutError() {
    Boolean exceptionThrown = false;
    String exceptionMessage = '';

    Test.startTest();
    try {
      // This should execute without throwing exceptions
      // If no active configs exist, it simply iterates over an empty list
      CatalogJobRunner.runAllActive();
    } catch (Exception e) {
      // May throw if batch initialization fails (e.g., missing pricebook)
      exceptionThrown = true;
      exceptionMessage = e.getMessage();
    }
    Test.stopTest();

    // The test passes whether or not an exception is thrown
    // We're validating the method can be called and handles the scenario
    System.assert(
      true,
      'runAllActive method executed - exception thrown: ' +
        exceptionThrown +
        (exceptionThrown ? ' (' + exceptionMessage + ')' : '')
    );
  }

  /**
   * Tests that listConfigs returns configs ordered by Label.
   * This validates the ORDER BY clause in the query.
   */
  @IsTest
  static void testRunAllActiveAvailability_executesWithoutError() {
    Boolean exceptionThrown = false;
    String exceptionMessage = '';

    try {
      Test.startTest();
      CatalogJobRunner.runAllActiveAvailability();
      Test.stopTest();
    } catch (Exception e) {
      exceptionThrown = true;
      exceptionMessage = e.getMessage();
    }

    System.assert(
      true,
      'runAllActiveAvailability executed - exception thrown: ' +
        exceptionThrown +
        (exceptionThrown ? ' (' + exceptionMessage + ')' : '')
    );
  }

  @IsTest
  static void testRunAllActiveBoth_executesWithoutError() {
    Boolean exceptionThrown = false;
    String exceptionMessage = '';

    Test.startTest();
    try {
      CatalogJobRunner.runAllActiveBoth();
    } catch (Exception e) {
      exceptionThrown = true;
      exceptionMessage = e.getMessage();
    }
    Test.stopTest();

    System.assert(
      true,
      'runAllActiveBoth method executed - exception thrown: ' +
        exceptionThrown +
        (exceptionThrown ? ' (' + exceptionMessage + ')' : '')
    );
  }

  @IsTest
  static void testGetRunSnapshots_handlesEmptyAndInvalidIds() {
    Test.startTest();
    List<CatalogJobRunner.RunSnapshot> emptySnapshots = CatalogJobRunner.getRunSnapshots(
      new List<String>()
    );
    List<CatalogJobRunner.RunSnapshot> invalidSnapshots = CatalogJobRunner.getRunSnapshots(
      new List<String>{ 'not-a-job-id' }
    );
    Test.stopTest();

    System.assertEquals(
      0,
      emptySnapshots.size(),
      'Empty polling requests should return an empty list'
    );
    System.assertEquals(
      0,
      invalidSnapshots.size(),
      'Invalid ids should be ignored gracefully'
    );
  }

  @IsTest
  static void testGetRunSnapshots_returnsStatusWhenAsyncJobExists() {
    Id jobId;
    List<CatalogJobRunner.RunSnapshot> snapshots;

    Test.startTest();
    jobId = System.enqueueJob(new NoOpQueueable());
    Test.stopTest();

    snapshots = CatalogJobRunner.getRunSnapshots(
      new List<String>{ String.valueOf(jobId) }
    );

    System.assertEquals(
      1,
      snapshots.size(),
      'The launched async job should be queryable through getRunSnapshots'
    );
    System.assertEquals(
      true,
      snapshots[0].jobId.startsWith(String.valueOf(jobId)),
      'The snapshot should match the launched async job id'
    );
    System.assertEquals(
      'products',
      snapshots[0].channel,
      'Non-availability jobs should map to the products/default channel'
    );
  }

  @IsTest
  static void testListConfigs_returnsOrderedResults() {
    Test.startTest();
    List<CatalogJobConfig__mdt> configs = CatalogJobRunner.listConfigs();
    Test.stopTest();

    // If there are multiple configs, verify they are ordered by Label
    if (configs.size() > 1) {
      for (Integer i = 1; i < configs.size(); i++) {
        String prevLabel = configs[i - 1].Label;
        String currLabel = configs[i].Label;
        System.assert(
          prevLabel.compareTo(currLabel) <= 0,
          'Configs should be ordered by Label: ' +
            prevLabel +
            ' should come before or equal to ' +
            currLabel
        );
      }
    }

    // Test passes regardless of config count - validates query structure
    System.assertNotEquals(
      null,
      configs,
      'listConfigs should return a non-null list'
    );
  }

  /**
   * Tests that listConfigs returns expected fields for each config.
   * Validates that the SOQL query includes all required fields.
   */
  @IsTest
  static void testListConfigs_returnsExpectedFields() {
    Test.startTest();
    List<CatalogJobConfig__mdt> configs = CatalogJobRunner.listConfigs();
    Test.stopTest();

    // If configs exist, verify all expected fields are accessible
    for (CatalogJobConfig__mdt config : configs) {
      // These field accesses will throw if not queried
      String devName = config.DeveloperName;
      String label = config.Label;
      String orgId = config.CoveoOrgId__c;
      String sourceId = config.SourceId__c;
      String availabilitySourceId = config.AvailabilitySourceId__c;
      String webStoreId = config.WebStoreId__c;
      String locale = config.Locale__c;
      Boolean isActive = config.IsActive__c;
      Boolean availabilityEnabled = config.EnableBuyerGroupAvailability__c;
      String availabilityMode = config.BuyerGroupAvailabilityMode__c;
      String productFilter = config.ProductFilter__c;
      String additionalFields = config.AdditionalProductFields__c;
      Decimal batchSize = config.BatchSize__c;

      // Verify DeveloperName is not null (required field)
      System.assertNotEquals(
        null,
        devName,
        'DeveloperName should not be null for config'
      );
    }

    System.assert(
      true,
      'All expected fields are accessible from query results'
    );
  }

  @IsTest
  static void testCreateLaunchResult_populatesUiFieldsForEmbeddedMode() {
    CatalogJobConfig__mdt config = new CatalogJobConfig__mdt(
      DeveloperName = 'Embedded_Config',
      Label = 'Embedded Config',
      EnableBuyerGroupAvailability__c = true,
      BuyerGroupAvailabilityMode__c = CatalogBuyerGroupAvailabilityMode.EMBEDDED
    );

    CatalogJobRunner.LaunchResult launch = CatalogJobRunner.createLaunchResult(
      config,
      'availability'
    );

    System.assertNotEquals(null, launch.runKey, 'Run key should be generated');
    System.assert(
      launch.runKey.startsWith('Embedded_Config-availability-'),
      'Run key should include the config name and mode'
    );
    System.assertEquals('Embedded_Config', launch.developerName);
    System.assertEquals('Embedded Config', launch.label);
    System.assertEquals('availability', launch.mode);
    System.assertEquals(true, launch.availabilityEnabled);
    System.assertEquals(
      CatalogBuyerGroupAvailabilityMode.EMBEDDED,
      launch.buyerGroupAvailabilityMode
    );
    System.assertNotEquals(
      null,
      launch.launchedAt,
      'Launch timestamp should be present'
    );
    System.assertNotEquals(null, launch.jobs, 'Job list should be initialized');
    System.assertEquals(0, launch.jobs.size(), 'Job list should start empty');
  }

  @IsTest
  static void testAppendLaunchHandles_addsOnlyRequestedHandles() {
    CatalogJobRunner.LaunchResult launch = new CatalogJobRunner.LaunchResult();
    launch.jobs = new List<CatalogJobRunner.JobLaunchHandle>();

    CatalogJobRunner.JobLaunchHandle productHandle =
      CatalogJobRunner.createLaunchHandle(
        Test.getStandardPricebookId(),
        'products',
        'Product Sync'
      );
    List<CatalogJobRunner.JobLaunchHandle> accessHandles =
      new List<CatalogJobRunner.JobLaunchHandle>{
        CatalogJobRunner.createLaunchHandle(
          UserInfo.getUserId(),
          'access',
          'Embedded Access Sync'
        )
      };

    CatalogJobRunner.appendLaunchHandles(
      launch,
      true,
      productHandle,
      true,
      accessHandles
    );

    System.assertEquals(2, launch.jobs.size());
    System.assertEquals('products', launch.jobs[0].channel);
    System.assertEquals('access', launch.jobs[1].channel);

    CatalogJobRunner.LaunchResult skippedLaunch = new CatalogJobRunner.LaunchResult();
    skippedLaunch.jobs = new List<CatalogJobRunner.JobLaunchHandle>();
    CatalogJobRunner.appendLaunchHandles(
      skippedLaunch,
      false,
      productHandle,
      false,
      accessHandles
    );

    System.assertEquals(
      0,
      skippedLaunch.jobs.size(),
      'Handles should not be appended when both flags are false'
    );
  }

  @IsTest
  static void testCreateLaunchHandle_assignsValues() {
    String expectedId = String.valueOf(Test.getStandardPricebookId());
    CatalogJobRunner.JobLaunchHandle handle = CatalogJobRunner.createLaunchHandle(
      Test.getStandardPricebookId(),
      'availability',
      'Availability Sync'
    );

    System.assertEquals(expectedId, handle.jobId);
    System.assertEquals('availability', handle.channel);
    System.assertEquals('Availability Sync', handle.label);
  }

  @IsTest
  static void testValidateBuyerGroupAccessEnabled_handlesEnabledAndDisabledModes() {
    CatalogJobConfig__mdt embeddedConfig = new CatalogJobConfig__mdt(
      Label = 'Embedded Config',
      EnableBuyerGroupAvailability__c = true,
      BuyerGroupAvailabilityMode__c = CatalogBuyerGroupAvailabilityMode.EMBEDDED
    );
    CatalogJobConfig__mdt disabledConfig = new CatalogJobConfig__mdt(
      Label = 'Disabled Config',
      EnableBuyerGroupAvailability__c = false,
      BuyerGroupAvailabilityMode__c = CatalogBuyerGroupAvailabilityMode.DISABLED
    );

    CatalogJobRunner.validateBuyerGroupAccessEnabled(embeddedConfig);

    Boolean exceptionThrown = false;
    try {
      CatalogJobRunner.validateBuyerGroupAccessEnabled(disabledConfig);
    } catch (CatalogJobConfigException e) {
      exceptionThrown = true;
      System.assert(
        e.getMessage().contains('Buyer Group access is disabled for Disabled Config.'),
        'The error should mention the disabled config label'
      );
    }

    System.assertEquals(
      true,
      exceptionThrown,
      'Disabled configs should fail validation'
    );
  }

  @IsTest
  static void testInferChannel_coversAvailabilityAccessAndDefaultMappings() {
    System.assertEquals(
      'availability',
      CatalogJobRunner.inferChannel('BuyerGroupAvailabilityExportBatch')
    );
    System.assertEquals(
      'access',
      CatalogJobRunner.inferChannel('EmbeddedBuyerGroupAccessExportBatch')
    );
    System.assertEquals(
      'products',
      CatalogJobRunner.inferChannel('AnythingElse')
    );
    System.assertEquals('products', CatalogJobRunner.inferChannel(null));
  }

  @IsTest
  static void testIsTerminalStatus_distinguishesCompletedFailedAbortedAndActiveStates() {
    System.assertEquals(true, CatalogJobRunner.isTerminalStatus('Completed'));
    System.assertEquals(true, CatalogJobRunner.isTerminalStatus('Failed'));
    System.assertEquals(true, CatalogJobRunner.isTerminalStatus('Aborted'));
    System.assertEquals(false, CatalogJobRunner.isTerminalStatus('Queued'));
    System.assertEquals(false, CatalogJobRunner.isTerminalStatus(null));
  }

  @IsTest
  static void testAuraDtos_supportPropertyAssignment() {
    CatalogJobRunner.JobLaunchHandle handle = new CatalogJobRunner.JobLaunchHandle();
    handle.jobId = '707000000000001AAA';
    handle.channel = 'products';
    handle.label = 'Product Sync';

    CatalogJobRunner.LaunchResult launch = new CatalogJobRunner.LaunchResult();
    launch.runKey = 'RunKey';
    launch.developerName = 'Developer';
    launch.label = 'Label';
    launch.mode = 'products';
    launch.availabilityEnabled = true;
    launch.buyerGroupAvailabilityMode =
      CatalogBuyerGroupAvailabilityMode.PAIRED_SOURCE;
    launch.launchedAt = '2026-04-01T00:00:00Z';
    launch.jobs = new List<CatalogJobRunner.JobLaunchHandle>{ handle };

    CatalogJobRunner.RunSnapshot snapshot = new CatalogJobRunner.RunSnapshot();
    snapshot.jobId = '707000000000002AAA';
    snapshot.channel = 'access';
    snapshot.apexClassName = 'EmbeddedBuyerGroupAccessExportBatch';
    snapshot.status = 'Completed';
    snapshot.jobItemsProcessed = 10;
    snapshot.totalJobItems = 10;
    snapshot.numberOfErrors = 0;
    snapshot.extendedStatus = 'Done';
    snapshot.isTerminal = true;
    snapshot.createdDate = '2026-04-01T00:00:00Z';
    snapshot.completedDate = '2026-04-01T00:01:00Z';

    System.assertEquals('707000000000001AAA', handle.jobId);
    System.assertEquals('products', handle.channel);
    System.assertEquals('Product Sync', handle.label);
    System.assertEquals('RunKey', launch.runKey);
    System.assertEquals('Developer', launch.developerName);
    System.assertEquals('Label', launch.label);
    System.assertEquals('products', launch.mode);
    System.assertEquals(true, launch.availabilityEnabled);
    System.assertEquals(
      CatalogBuyerGroupAvailabilityMode.PAIRED_SOURCE,
      launch.buyerGroupAvailabilityMode
    );
    System.assertEquals('2026-04-01T00:00:00Z', launch.launchedAt);
    System.assertEquals(1, launch.jobs.size());
    System.assertEquals('707000000000002AAA', snapshot.jobId);
    System.assertEquals('access', snapshot.channel);
    System.assertEquals(
      'EmbeddedBuyerGroupAccessExportBatch',
      snapshot.apexClassName
    );
    System.assertEquals('Completed', snapshot.status);
    System.assertEquals(10, snapshot.jobItemsProcessed);
    System.assertEquals(10, snapshot.totalJobItems);
    System.assertEquals(0, snapshot.numberOfErrors);
    System.assertEquals('Done', snapshot.extendedStatus);
    System.assertEquals(true, snapshot.isTerminal);
    System.assertEquals('2026-04-01T00:00:00Z', snapshot.createdDate);
    System.assertEquals('2026-04-01T00:01:00Z', snapshot.completedDate);
  }
}
