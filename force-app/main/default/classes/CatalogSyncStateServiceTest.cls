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
    return new Catalog_Sync_State__c(
      ResolvedTargetKey__c = CatalogSyncStateService.buildResolvedTargetKey(
        config
      ),
      BaselineFullConfigDeveloperName__c =
        config.BaselineFullConfigDeveloperName__c,
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
      WHERE ResolvedTargetKey__c = :CatalogSyncStateService.buildResolvedTargetKey(
        config
      )
      LIMIT 1
    ];

    System.assertEquals('FULL_CONFIG', stateRecord.BaselineFullConfigDeveloperName__c);
    System.assertEquals(cutoff, stateRecord.LastSuccessfulFullSyncAt__c);
    System.assertEquals(cutoff, stateRecord.LastSuccessfulSyncAt__c);
    System.assertEquals(CatalogSyncMode.FULL, stateRecord.LastRunMode__c);
    System.assertEquals('FULL_CONFIG', stateRecord.LastSuccessfulConfigDeveloperName__c);
  }

  @IsTest
  static void testRecordSuccessfulDeltaSync_updatesExistingState() {
    CatalogJobConfig__mdt fullConfig = createConfig('FULL_CONFIG', 'Full', null);
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
      WHERE ResolvedTargetKey__c = :CatalogSyncStateService.buildResolvedTargetKey(
        deltaConfig
      )
      LIMIT 1
    ];

    System.assertEquals('FULL_CONFIG', stateRecord.BaselineFullConfigDeveloperName__c);
    System.assertEquals(fullCutoff, stateRecord.LastSuccessfulFullSyncAt__c);
    System.assertEquals(deltaCutoff, stateRecord.LastSuccessfulSyncAt__c);
    System.assertEquals(CatalogSyncMode.DELTA, stateRecord.LastRunMode__c);
    System.assertEquals(
      'DELTA_CONFIG',
      stateRecord.LastSuccessfulConfigDeveloperName__c
    );
  }

  @IsTest
  static void testEvaluateDeltaReadiness_requiresBaselineReference() {
    CatalogJobConfig__mdt deltaConfig = createConfig('DELTA_ONLY', 'Delta', null);

    CatalogSyncStateService.DeltaReadiness readiness =
      CatalogSyncStateService.evaluateDeltaReadiness(deltaConfig);

    System.assertEquals(false, readiness.isReady);
    System.assert(
      readiness.message.contains('BaselineFullConfigDeveloperName__c is required')
    );
  }

  @IsTest
  static void testEvaluateDeltaReadiness_rejectsBaselineTargetMismatch() {
    CatalogJobConfig__mdt fullConfig = createConfig('FULL_CONFIG', 'Full', null);
    fullConfig.SourceId__c = 'full-source';
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_CONFIG',
      'Delta',
      'FULL_CONFIG'
    );
    deltaConfig.SourceId__c = 'delta-source';

    CatalogSyncStateService.testConfigsByDeveloperName =
      new Map<String, CatalogJobConfig__mdt>{ 'FULL_CONFIG' => fullConfig };

    CatalogSyncStateService.DeltaReadiness readiness =
      CatalogSyncStateService.evaluateDeltaReadiness(deltaConfig);

    System.assertEquals(false, readiness.isReady);
    System.assert(readiness.message.contains('does not resolve to the same export target'));
  }

  @IsTest
  static void testEvaluateDeltaReadiness_rejectsMissingBaselineState() {
    CatalogJobConfig__mdt fullConfig = createConfig('FULL_CONFIG', 'Full', null);
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_CONFIG',
      'Delta',
      'FULL_CONFIG'
    );

    CatalogSyncStateService.testConfigsByDeveloperName =
      new Map<String, CatalogJobConfig__mdt>{ 'FULL_CONFIG' => fullConfig };

    CatalogSyncStateService.DeltaReadiness readiness =
      CatalogSyncStateService.evaluateDeltaReadiness(deltaConfig);

    System.assertEquals(false, readiness.isReady);
    System.assert(readiness.message.contains('Run the baseline full sync once'));
  }

  @IsTest
  static void testEvaluateDeltaReadiness_acceptsMatchingBaselineState() {
    CatalogJobConfig__mdt fullConfig = createConfig('FULL_CONFIG', 'Full', null);
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_CONFIG',
      'Delta',
      'FULL_CONFIG'
    );
    Datetime fullCutoff = System.now().addHours(-3);
    Datetime deltaCutoff = System.now().addHours(-1);

    CatalogSyncStateService.testConfigsByDeveloperName =
      new Map<String, CatalogJobConfig__mdt>{ 'FULL_CONFIG' => fullConfig };
    CatalogSyncStateService.testStatesByTargetKey =
      new Map<String, Catalog_Sync_State__c>{
        CatalogSyncStateService.buildResolvedTargetKey(deltaConfig) => createState(
          deltaConfig,
          fullCutoff,
          deltaCutoff,
          CatalogSyncMode.DELTA,
          'DELTA_CONFIG'
        )
      };

    CatalogSyncStateService.DeltaReadiness readiness =
      CatalogSyncStateService.evaluateDeltaReadiness(deltaConfig);

    System.assertEquals(true, readiness.isReady);
    System.assertEquals('Delta sync is ready.', readiness.message);
    System.assertEquals(deltaCutoff, readiness.stateRecord.LastSuccessfulSyncAt__c);
  }

  @IsTest
  static void testGetSnapshotsByDeveloperName_includesDeltaReadinessAndWatermarks() {
    CatalogJobConfig__mdt fullConfig = createConfig('FULL_CONFIG', 'Full', null);
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_CONFIG',
      'Delta',
      'FULL_CONFIG'
    );
    Datetime fullCutoff = Datetime.newInstanceGmt(2026, 4, 1, 10, 0, 0);
    Datetime deltaCutoff = Datetime.newInstanceGmt(2026, 4, 1, 12, 0, 0);

    CatalogSyncStateService.testConfigsByDeveloperName =
      new Map<String, CatalogJobConfig__mdt>{ 'FULL_CONFIG' => fullConfig };
    CatalogSyncStateService.testStatesByTargetKey =
      new Map<String, Catalog_Sync_State__c>{
        CatalogSyncStateService.buildResolvedTargetKey(fullConfig) => createState(
          deltaConfig,
          fullCutoff,
          deltaCutoff,
          CatalogSyncMode.DELTA,
          'DELTA_CONFIG'
        )
      };

    Map<String, CatalogSyncStateService.Snapshot> snapshots =
      CatalogSyncStateService.getSnapshotsByDeveloperName(
        new List<CatalogJobConfig__mdt>{ fullConfig, deltaConfig }
      );

    System.assertEquals(true, snapshots.get('FULL_CONFIG').deltaReady);
    System.assertEquals(false, String.isBlank(snapshots.get('FULL_CONFIG').resolvedTargetKey));
    System.assertEquals(true, snapshots.get('DELTA_CONFIG').deltaReady);
    System.assertEquals('FULL_CONFIG', snapshots.get('DELTA_CONFIG').baselineFullConfigDeveloperName);
    System.assertEquals(
      '2026-04-01T10:00:00Z',
      snapshots.get('DELTA_CONFIG').lastSuccessfulFullSyncAt
    );
    System.assertEquals(
      '2026-04-01T12:00:00Z',
      snapshots.get('DELTA_CONFIG').lastSuccessfulSyncAt
    );
    System.assertEquals(CatalogSyncMode.DELTA, snapshots.get('DELTA_CONFIG').lastRunMode);
  }
}
