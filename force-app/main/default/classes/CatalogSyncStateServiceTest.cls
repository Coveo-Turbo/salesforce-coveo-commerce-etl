@IsTest
private class CatalogSyncStateServiceTest {
  @TestSetup
  static void clearOverrides() {
    CatalogSyncStateService.clearTestOverrides();
  }

  private static CatalogJobConfig__mdt createConfig(
    String developerName,
    String syncMode,
    String baselineFullConfigDeveloperName
  ) {
    return new CatalogJobConfig__mdt(
      DeveloperName = developerName,
      MasterLabel = developerName,
      CoveoOrgId__c = 'org-123',
      SourceId__c = 'source-456',
      Locale__c = 'en-US',
      BuilderType__c = 'Default',
      SyncMode__c = syncMode,
      BaselineFullConfigDeveloperName__c = baselineFullConfigDeveloperName
    );
  }

  private static Catalog_Sync_State__c createState(
    CatalogJobConfig__mdt config,
    Datetime fullCutoff,
    Datetime syncCutoff,
    String runMode,
    String configDeveloperName
  ) {
    return createState(
      config,
      fullCutoff,
      syncCutoff,
      runMode,
      configDeveloperName,
      null,
      null,
      null,
      null
    );
  }

  private static Catalog_Sync_State__c createState(
    CatalogJobConfig__mdt config,
    Datetime fullCutoff,
    Datetime syncCutoff,
    String runMode,
    String configDeveloperName,
    String currentProductJobId,
    String currentProductRunMode,
    String currentProductConfigDeveloperName,
    Datetime currentProductStartedAt
  ) {
    return new Catalog_Sync_State__c(
      ResolvedTargetKey__c = CatalogSyncStateService.buildResolvedTargetKey(
        config
      ),
      BaselineFullConfigDeveloperName__c = config.BaselineFullConfigDeveloperName__c,
      CurrentProductJobId__c = currentProductJobId,
      CurrentProductRunMode__c = currentProductRunMode,
      CurrentProductConfigDeveloperName__c = currentProductConfigDeveloperName,
      CurrentProductStartedAt__c = currentProductStartedAt,
      LastSuccessfulFullSyncAt__c = fullCutoff,
      LastSuccessfulSyncAt__c = syncCutoff,
      LastRunMode__c = runMode,
      LastSuccessfulConfigDeveloperName__c = configDeveloperName
    );
  }

  @IsTest
  static void testBuildResolvedTargetKey_ignoresExtraFieldOrdering() {
    CatalogJobConfig__mdt firstConfig = createConfig('FIRST', 'Full', null);
    firstConfig.AdditionalProductFields__c = 'Family, Description';

    CatalogJobConfig__mdt secondConfig = createConfig('SECOND', 'Full', null);
    secondConfig.AdditionalProductFields__c = 'Description,Family';

    System.assertEquals(
      CatalogSyncStateService.buildResolvedTargetKey(firstConfig),
      CatalogSyncStateService.buildResolvedTargetKey(secondConfig)
    );
  }

  @IsTest
  static void testBuildResolvedTargetKey_canonicalizesAndScopesStorePricebooks() {
    CatalogJobConfig__mdt firstConfig = createConfig('FIRST', 'Full', null);
    firstConfig.PricebookIds__c = '01s000000000001AAA,01s000000000002AAA';
    firstConfig.WebStoreIds__c = '0ZE000000000001AAA,0ZE000000000002AAA';

    CatalogJobConfig__mdt reorderedConfig = createConfig(
      'SECOND',
      'Full',
      null
    );
    reorderedConfig.PricebookIds__c = '01s000000000002AAA, 01s000000000001AAA';
    reorderedConfig.WebStoreIds__c = '0ZE000000000002AAA, 0ZE000000000001AAA';

    System.assertEquals(
      CatalogSyncStateService.buildResolvedTargetKey(firstConfig),
      CatalogSyncStateService.buildResolvedTargetKey(reorderedConfig)
    );

    reorderedConfig.PricebookIds__c = '01s000000000003AAA';
    System.assertNotEquals(
      CatalogSyncStateService.buildResolvedTargetKey(firstConfig),
      CatalogSyncStateService.buildResolvedTargetKey(reorderedConfig)
    );
  }

  @IsTest
  static void testBuildResolvedTargetKey_normalizesIdDelimitersAndIdLength() {
    Id firstPricebookId = Id.valueOf('01s000000000001');
    Id secondPricebookId = Id.valueOf('01s000000000002');
    Id firstStoreId = Id.valueOf('0ZE000000000001');
    Id secondStoreId = Id.valueOf('0ZE000000000002');
    CatalogJobConfig__mdt firstConfig = createConfig('FIRST', 'Full', null);
    firstConfig.PricebookIds__c =
      String.valueOf(firstPricebookId) +
      ';\n' +
      String.valueOf(secondPricebookId);
    firstConfig.WebStoreIds__c =
      String.valueOf(firstStoreId) +
      '\r\n' +
      String.valueOf(secondStoreId);

    CatalogJobConfig__mdt secondConfig = createConfig('SECOND', 'Full', null);
    secondConfig.PricebookIds__c = '01s000000000002,01s000000000001';
    secondConfig.WebStoreIds__c = '0ZE000000000002;0ZE000000000001';

    System.assertEquals(
      CatalogSyncStateService.buildResolvedTargetKey(firstConfig),
      CatalogSyncStateService.buildResolvedTargetKey(secondConfig),
      'Target keys should use the same delimiter and ID normalization as runtime resolution'
    );
  }

  @IsTest
  static void testRecordSuccessfulFullSync_createsState() {
    CatalogJobConfig__mdt config = createConfig('FULL_CONFIG', 'Full', null);
    Datetime cutoff = System.now();

    Test.startTest();
    CatalogSyncStateService.recordSuccessfulFullSync(config, cutoff);
    Test.stopTest();

    Catalog_Sync_State__c stateRecord = [
      SELECT
        ResolvedTargetKey__c,
        BaselineFullConfigDeveloperName__c,
        LastSuccessfulFullSyncAt__c,
        LastSuccessfulSyncAt__c,
        LastRunMode__c,
        LastSuccessfulConfigDeveloperName__c
      FROM Catalog_Sync_State__c
      WHERE
        ResolvedTargetKey__c = :CatalogSyncStateService.buildResolvedTargetKey(
          config
        )
      LIMIT 1
    ];

    System.assertEquals(
      'FULL_CONFIG',
      stateRecord.BaselineFullConfigDeveloperName__c
    );
    System.assertEquals(cutoff, stateRecord.LastSuccessfulFullSyncAt__c);
    System.assertEquals(cutoff, stateRecord.LastSuccessfulSyncAt__c);
    System.assertEquals(CatalogSyncMode.FULL, stateRecord.LastRunMode__c);
    System.assertEquals(
      'FULL_CONFIG',
      stateRecord.LastSuccessfulConfigDeveloperName__c
    );
  }

  @IsTest
  static void testRecordSuccessfulDeltaSync_updatesExistingState() {
    CatalogJobConfig__mdt fullConfig = createConfig(
      'FULL_CONFIG',
      'Full',
      null
    );
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_CONFIG',
      'Delta',
      'FULL_CONFIG'
    );
    Datetime fullCutoff = System.now().addHours(-2);
    Datetime deltaCutoff = System.now();

    CatalogSyncStateService.recordSuccessfulFullSync(fullConfig, fullCutoff);

    Test.startTest();
    CatalogSyncStateService.recordSuccessfulDeltaSync(deltaConfig, deltaCutoff);
    Test.stopTest();

    Catalog_Sync_State__c stateRecord = [
      SELECT
        BaselineFullConfigDeveloperName__c,
        LastSuccessfulFullSyncAt__c,
        LastSuccessfulSyncAt__c,
        LastRunMode__c,
        LastSuccessfulConfigDeveloperName__c
      FROM Catalog_Sync_State__c
      WHERE
        ResolvedTargetKey__c = :CatalogSyncStateService.buildResolvedTargetKey(
          deltaConfig
        )
      LIMIT 1
    ];

    System.assertEquals(
      'FULL_CONFIG',
      stateRecord.BaselineFullConfigDeveloperName__c
    );
    System.assertEquals(fullCutoff, stateRecord.LastSuccessfulFullSyncAt__c);
    System.assertEquals(deltaCutoff, stateRecord.LastSuccessfulSyncAt__c);
    System.assertEquals(CatalogSyncMode.DELTA, stateRecord.LastRunMode__c);
    System.assertEquals(
      'DELTA_CONFIG',
      stateRecord.LastSuccessfulConfigDeveloperName__c
    );
  }

  @IsTest
  static void testRecordStartedProductSync_tracksCurrentProductRun() {
    CatalogJobConfig__mdt config = createConfig('FULL_CONFIG', 'Full', null);
    Datetime startedAt = System.now();

    Test.startTest();
    CatalogSyncStateService.recordStartedProductSync(
      config,
      CatalogSyncMode.FULL,
      UserInfo.getUserId(),
      startedAt
    );
    Test.stopTest();

    Catalog_Sync_State__c stateRecord = [
      SELECT
        CurrentProductJobId__c,
        CurrentProductRunMode__c,
        CurrentProductConfigDeveloperName__c,
        CurrentProductStartedAt__c,
        RecentProductRunsJson__c
      FROM Catalog_Sync_State__c
      WHERE
        ResolvedTargetKey__c = :CatalogSyncStateService.buildResolvedTargetKey(
          config
        )
      LIMIT 1
    ];

    System.assertEquals(
      String.valueOf(UserInfo.getUserId()),
      stateRecord.CurrentProductJobId__c
    );
    System.assertEquals(
      CatalogSyncMode.FULL,
      stateRecord.CurrentProductRunMode__c
    );
    System.assertEquals(
      'FULL_CONFIG',
      stateRecord.CurrentProductConfigDeveloperName__c
    );
    System.assertEquals(startedAt, stateRecord.CurrentProductStartedAt__c);
    System.assert(stateRecord.RecentProductRunsJson__c.contains('FULL_CONFIG'));
    System.assert(
      stateRecord.RecentProductRunsJson__c.contains(
        String.valueOf(UserInfo.getUserId())
      )
    );
  }

  @IsTest
  static void testRecordSuccessfulFullSync_marksRecentRunCompleted() {
    CatalogJobConfig__mdt config = createConfig('FULL_CONFIG', 'Full', null);
    Datetime startedAt = Datetime.newInstanceGmt(2026, 4, 2, 9, 15, 0);
    Datetime cutoff = Datetime.newInstanceGmt(2026, 4, 2, 9, 45, 0);
    Id jobId = UserInfo.getUserId();

    CatalogSyncStateService.recordStartedProductSync(
      config,
      CatalogSyncMode.FULL,
      jobId,
      startedAt
    );

    Test.startTest();
    CatalogSyncStateService.recordSuccessfulFullSync(config, cutoff);
    Test.stopTest();

    Catalog_Sync_State__c stateRecord = [
      SELECT RecentProductRunsJson__c
      FROM Catalog_Sync_State__c
      WHERE
        ResolvedTargetKey__c = :CatalogSyncStateService.buildResolvedTargetKey(
          config
        )
      LIMIT 1
    ];

    System.assert(stateRecord.RecentProductRunsJson__c.contains('Completed'));
    System.assert(
      stateRecord.RecentProductRunsJson__c.contains('2026-04-02T09:45:00Z')
    );
  }

  @IsTest
  static void testEvaluateDeltaReadiness_requiresBaselineReference() {
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_ONLY',
      'Delta',
      null
    );

    CatalogSyncStateService.DeltaReadiness readiness = CatalogSyncStateService.evaluateDeltaReadiness(
      deltaConfig
    );

    System.assertEquals(false, readiness.isReady);
    System.assert(
      readiness.message.contains(
        'BaselineFullConfigDeveloperName__c is required'
      )
    );
  }

  @IsTest
  static void testEvaluateDeltaReadiness_rejectsBaselineTargetMismatch() {
    CatalogJobConfig__mdt fullConfig = createConfig(
      'FULL_CONFIG',
      'Full',
      null
    );
    fullConfig.SourceId__c = 'full-source';
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_CONFIG',
      'Delta',
      'FULL_CONFIG'
    );
    deltaConfig.SourceId__c = 'delta-source';

    CatalogSyncStateService.testConfigsByDeveloperName = new Map<String, CatalogJobConfig__mdt>{
      'FULL_CONFIG' => fullConfig
    };

    CatalogSyncStateService.DeltaReadiness readiness = CatalogSyncStateService.evaluateDeltaReadiness(
      deltaConfig
    );

    System.assertEquals(false, readiness.isReady);
    System.assert(
      readiness.message.contains('does not resolve to the same export target')
    );
  }

  @IsTest
  static void testEvaluateDeltaReadiness_rejectsMissingBaselineState() {
    CatalogJobConfig__mdt fullConfig = createConfig(
      'FULL_CONFIG',
      'Full',
      null
    );
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_CONFIG',
      'Delta',
      'FULL_CONFIG'
    );

    CatalogSyncStateService.testConfigsByDeveloperName = new Map<String, CatalogJobConfig__mdt>{
      'FULL_CONFIG' => fullConfig
    };

    CatalogSyncStateService.DeltaReadiness readiness = CatalogSyncStateService.evaluateDeltaReadiness(
      deltaConfig
    );

    System.assertEquals(false, readiness.isReady);
    System.assert(
      readiness.message.contains('Run the baseline full sync once')
    );
  }

  @IsTest
  static void testEvaluateDeltaReadiness_acceptsMatchingBaselineState() {
    CatalogJobConfig__mdt fullConfig = createConfig(
      'FULL_CONFIG',
      'Full',
      null
    );
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_CONFIG',
      'Delta',
      'FULL_CONFIG'
    );
    Datetime fullCutoff = System.now().addHours(-3);
    Datetime deltaCutoff = System.now().addHours(-1);

    CatalogSyncStateService.testConfigsByDeveloperName = new Map<String, CatalogJobConfig__mdt>{
      'FULL_CONFIG' => fullConfig
    };
    CatalogSyncStateService.testStatesByTargetKey = new Map<String, Catalog_Sync_State__c>{
      CatalogSyncStateService.buildResolvedTargetKey(
        deltaConfig
      ) => createState(
        deltaConfig,
        fullCutoff,
        deltaCutoff,
        CatalogSyncMode.DELTA,
        'DELTA_CONFIG'
      )
    };

    CatalogSyncStateService.DeltaReadiness readiness = CatalogSyncStateService.evaluateDeltaReadiness(
      deltaConfig
    );

    System.assertEquals(true, readiness.isReady);
    System.assertEquals('Delta sync is ready.', readiness.message);
    System.assertEquals(
      deltaCutoff,
      readiness.stateRecord.LastSuccessfulSyncAt__c
    );
  }

  @IsTest
  static void testEvaluateDeltaReadiness_rejectsActiveFullRun() {
    CatalogJobConfig__mdt fullConfig = createConfig(
      'FULL_CONFIG',
      'Full',
      null
    );
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_CONFIG',
      'Delta',
      'FULL_CONFIG'
    );
    Datetime fullCutoff = Datetime.newInstanceGmt(2026, 4, 1, 10, 0, 0);
    String trackedJobId = '707000000000001AAA';

    CatalogSyncStateService.testConfigsByDeveloperName = new Map<String, CatalogJobConfig__mdt>{
      'FULL_CONFIG' => fullConfig
    };
    CatalogSyncStateService.testStatesByTargetKey = new Map<String, Catalog_Sync_State__c>{
      CatalogSyncStateService.buildResolvedTargetKey(
        deltaConfig
      ) => createState(
        deltaConfig,
        fullCutoff,
        fullCutoff,
        CatalogSyncMode.FULL,
        'FULL_CONFIG',
        trackedJobId,
        CatalogSyncMode.FULL,
        'FULL_CONFIG',
        Datetime.newInstanceGmt(2026, 4, 2, 9, 15, 0)
      )
    };
    CatalogSyncStateService.testAsyncJobStatusesById = new Map<String, String>{
      trackedJobId => 'Processing'
    };

    CatalogSyncStateService.DeltaReadiness readiness = CatalogSyncStateService.evaluateDeltaReadiness(
      deltaConfig
    );

    System.assertEquals(false, readiness.isReady);
    System.assert(readiness.message.contains('currently running'));
  }

  @IsTest
  static void testGetSnapshotsByDeveloperName_includesDeltaReadinessAndWatermarks() {
    CatalogJobConfig__mdt fullConfig = createConfig(
      'FULL_CONFIG',
      'Full',
      null
    );
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_CONFIG',
      'Delta',
      'FULL_CONFIG'
    );
    Datetime fullCutoff = Datetime.newInstanceGmt(2026, 4, 1, 10, 0, 0);
    Datetime deltaCutoff = Datetime.newInstanceGmt(2026, 4, 1, 12, 0, 0);

    CatalogSyncStateService.testConfigsByDeveloperName = new Map<String, CatalogJobConfig__mdt>{
      'FULL_CONFIG' => fullConfig
    };
    CatalogSyncStateService.testStatesByTargetKey = new Map<String, Catalog_Sync_State__c>{
      CatalogSyncStateService.buildResolvedTargetKey(fullConfig) => createState(
        deltaConfig,
        fullCutoff,
        deltaCutoff,
        CatalogSyncMode.DELTA,
        'DELTA_CONFIG'
      )
    };

    Map<String, CatalogSyncStateService.Snapshot> snapshots = CatalogSyncStateService.getSnapshotsByDeveloperName(
      new List<CatalogJobConfig__mdt>{ fullConfig, deltaConfig }
    );

    System.assertEquals(true, snapshots.get('FULL_CONFIG').deltaReady);
    System.assertEquals(
      false,
      String.isBlank(snapshots.get('FULL_CONFIG').resolvedTargetKey)
    );
    System.assertEquals(true, snapshots.get('DELTA_CONFIG').deltaReady);
    System.assertEquals(
      'FULL_CONFIG',
      snapshots.get('DELTA_CONFIG').baselineFullConfigDeveloperName
    );
    System.assertEquals(
      '2026-04-01T10:00:00Z',
      snapshots.get('DELTA_CONFIG').lastSuccessfulFullSyncAt
    );
    System.assertEquals(
      '2026-04-01T12:00:00Z',
      snapshots.get('DELTA_CONFIG').lastSuccessfulSyncAt
    );
    System.assertEquals(
      CatalogSyncMode.DELTA,
      snapshots.get('DELTA_CONFIG').lastRunMode
    );
  }

  @IsTest
  static void testGetSnapshotsByDeveloperName_includesActiveProductRunDetails() {
    CatalogJobConfig__mdt fullConfig = createConfig(
      'FULL_CONFIG',
      'Full',
      null
    );
    Datetime fullCutoff = Datetime.newInstanceGmt(2026, 4, 1, 10, 0, 0);
    Datetime startedAt = Datetime.newInstanceGmt(2026, 4, 2, 9, 15, 0);
    String trackedJobId = '707000000000001AAA';

    CatalogSyncStateService.testStatesByTargetKey = new Map<String, Catalog_Sync_State__c>{
      CatalogSyncStateService.buildResolvedTargetKey(fullConfig) => createState(
        fullConfig,
        fullCutoff,
        fullCutoff,
        CatalogSyncMode.FULL,
        'FULL_CONFIG',
        trackedJobId,
        CatalogSyncMode.FULL,
        'FULL_CONFIG',
        startedAt
      )
    };
    CatalogSyncStateService.testAsyncJobStatusesById = new Map<String, String>{
      trackedJobId => 'Processing'
    };
    CatalogSyncStateService.testAsyncJobCreatedDatesById = new Map<String, Datetime>{
      trackedJobId => startedAt
    };

    Map<String, CatalogSyncStateService.Snapshot> snapshots = CatalogSyncStateService.getSnapshotsByDeveloperName(
      new List<CatalogJobConfig__mdt>{ fullConfig }
    );

    CatalogSyncStateService.Snapshot snapshot = snapshots.get('FULL_CONFIG');
    System.assertEquals(trackedJobId, snapshot.currentProductJobId);
    System.assertEquals('Processing', snapshot.currentProductJobStatus);
    System.assertEquals(CatalogSyncMode.FULL, snapshot.currentProductRunMode);
    System.assertEquals(
      'FULL_CONFIG',
      snapshot.currentProductConfigDeveloperName
    );
    System.assertEquals(
      '2026-04-02T09:15:00Z',
      snapshot.currentProductStartedAt
    );
    System.assertEquals(true, snapshot.currentProductIsActive);
  }

  @IsTest
  static void testGetSnapshotsByDeveloperName_includesRecentCompletedProductRuns() {
    CatalogJobConfig__mdt fullConfig = createConfig(
      'FULL_CONFIG',
      'Full',
      null
    );
    Datetime fullCutoff = Datetime.newInstanceGmt(2026, 4, 1, 10, 0, 0);
    Catalog_Sync_State__c stateRecord = createState(
      fullConfig,
      fullCutoff,
      fullCutoff,
      CatalogSyncMode.FULL,
      'FULL_CONFIG'
    );
    stateRecord.RecentProductRunsJson__c = JSON.serialize(
      new List<Object>{
        new Map<String, Object>{
          'jobId' => '707000000000001AAA',
          'runMode' => CatalogSyncMode.FULL,
          'configDeveloperName' => 'FULL_CONFIG',
          'status' => 'Completed',
          'startedAt' => '2026-04-02T09:15:00Z',
          'completedAt' => '2026-04-02T09:45:00Z'
        }
      }
    );

    CatalogSyncStateService.testStatesByTargetKey = new Map<String, Catalog_Sync_State__c>{
      CatalogSyncStateService.buildResolvedTargetKey(fullConfig) => stateRecord
    };

    Map<String, CatalogSyncStateService.Snapshot> snapshots = CatalogSyncStateService.getSnapshotsByDeveloperName(
      new List<CatalogJobConfig__mdt>{ fullConfig }
    );

    CatalogSyncStateService.Snapshot snapshot = snapshots.get('FULL_CONFIG');
    System.assertEquals(false, snapshot.currentProductIsActive);
    System.assertEquals(1, snapshot.recentProductRuns.size());
    System.assertEquals(
      '707000000000001AAA',
      snapshot.recentProductRuns[0].jobId
    );
    System.assertEquals('Completed', snapshot.recentProductRuns[0].status);
    System.assertEquals(true, snapshot.recentProductRuns[0].isTerminal);
    System.assertEquals(
      '2026-04-02T09:45:00Z',
      snapshot.recentProductRuns[0].completedAt
    );
  }

  @IsTest
  static void testGetSnapshotsByDeveloperName_blocksDeltaWhileFullRunIsActive() {
    CatalogJobConfig__mdt fullConfig = createConfig(
      'FULL_CONFIG',
      'Full',
      null
    );
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_CONFIG',
      'Delta',
      'FULL_CONFIG'
    );
    Datetime fullCutoff = Datetime.newInstanceGmt(2026, 4, 1, 10, 0, 0);
    String trackedJobId = '707000000000001AAA';

    CatalogSyncStateService.testConfigsByDeveloperName = new Map<String, CatalogJobConfig__mdt>{
      'FULL_CONFIG' => fullConfig
    };
    CatalogSyncStateService.testStatesByTargetKey = new Map<String, Catalog_Sync_State__c>{
      CatalogSyncStateService.buildResolvedTargetKey(
        deltaConfig
      ) => createState(
        deltaConfig,
        fullCutoff,
        fullCutoff,
        CatalogSyncMode.FULL,
        'FULL_CONFIG',
        trackedJobId,
        CatalogSyncMode.FULL,
        'FULL_CONFIG',
        Datetime.newInstanceGmt(2026, 4, 2, 9, 15, 0)
      )
    };
    CatalogSyncStateService.testAsyncJobStatusesById = new Map<String, String>{
      trackedJobId => 'Processing'
    };

    Map<String, CatalogSyncStateService.Snapshot> snapshots = CatalogSyncStateService.getSnapshotsByDeveloperName(
      new List<CatalogJobConfig__mdt>{ fullConfig, deltaConfig }
    );

    System.assertEquals(false, snapshots.get('DELTA_CONFIG').deltaReady);
    System.assert(
      snapshots.get('DELTA_CONFIG')
        .deltaReadinessMessage.contains('currently running')
    );
  }
}
