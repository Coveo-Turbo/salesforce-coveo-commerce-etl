@IsTest
private class CatalogDeltaPipelineTest {
  private class NoOpQueueable implements Queueable {
    public void execute(QueueableContext context) {
    }
  }

  private static CatalogJobConfig__mdt createConfig(
    String developerName,
    String mode
  ) {
    return new CatalogJobConfig__mdt(
      DeveloperName = developerName,
      MasterLabel = developerName,
      CoveoOrgId__c = 'org-63',
      SourceId__c = 'source-63',
      Locale__c = 'en-US',
      BuilderType__c = 'Default',
      SyncMode__c = mode,
      BaselineFullConfigDeveloperName__c = mode == CatalogSyncMode.DELTA
        ? 'FULL_63'
        : null
    );
  }

  private static Product2 createProduct(String code, String family) {
    Product2 product = new Product2(
      Name = code,
      ProductCode = code,
      StockKeepingUnit = code,
      Family = family,
      IsActive = true
    );
    insert product;
    return product;
  }

  private static Catalog_Delta_Run__c createRun(
    CatalogJobConfig__mdt config,
    String stage
  ) {
    Catalog_Delta_Run__c run = new Catalog_Delta_Run__c(
      ResolvedTargetKey__c = CatalogSyncStateService.buildResolvedTargetKey(
        config
      ),
      ConfigDeveloperName__c = config.DeveloperName,
      BaselineTimestamp__c = System.now().addHours(-1),
      CutoffTimestamp__c = System.now().addHours(1),
      Status__c = CatalogDeltaRunService.STATUS_RUNNING,
      Stage__c = stage,
      StandardPricebookId__c = Test.getStandardPricebookId(),
      PricebookScopeFiltered__c = false,
      CleanupStatus__c = CatalogDeltaRunService.CLEANUP_PENDING
    );
    insert run;
    return run;
  }

  private static List<SObject> collectScope(Database.QueryLocator locator) {
    List<SObject> scope = new List<SObject>();
    Database.QueryLocatorIterator iterator = locator.iterator();
    while (iterator.hasNext()) {
      scope.add((SObject) iterator.next());
    }
    return scope;
  }

  @TestSetup
  static void resetHooks() {
    CatalogDeltaRunService.suppressChainingInTests = true;
    CatalogDeltaRunService.lastRequestedStage = null;
    CatalogDeltaRunService.lastRequestedDepth = null;
  }

  @IsTest
  static void testProductDiscoveryUsesCatalogAndProductFilterBeforeStaging() {
    Product2 included = createProduct('INCLUDED-63', 'Hardware');
    Product2 wrongFamily = createProduct('WRONG-FAMILY-63', 'Software');
    createProduct('OUTSIDE-CATALOG-63', 'Hardware');

    ProductCatalog catalog = new ProductCatalog(Name = 'Catalog 63');
    insert catalog;
    ProductCategory category = new ProductCategory(
      Name = 'Category 63',
      CatalogId = catalog.Id
    );
    insert category;
    insert new List<ProductCategoryProduct>{
      new ProductCategoryProduct(
        ProductId = included.Id,
        ProductCategoryId = category.Id
      ),
      new ProductCategoryProduct(
        ProductId = wrongFamily.Id,
        ProductCategoryId = category.Id
      )
    };

    CatalogJobConfig__mdt config = createConfig(
      'DELTA_PRODUCT_SCOPE_63',
      CatalogSyncMode.DELTA
    );
    config.CatalogId__c = catalog.Id;
    config.ProductFilter__c = 'Family = \'Hardware\'';
    Catalog_Delta_Run__c run = createRun(
      config,
      CatalogDeltaStageBatch.DISCOVER_PRODUCTS
    );
    CatalogDeltaStageBatch batch = new CatalogDeltaStageBatch(
      run.Id,
      CatalogDeltaStageBatch.DISCOVER_PRODUCTS,
      0,
      config
    );

    List<SObject> scope = collectScope(batch.start(null));
    System.assertEquals(1, scope.size());
    System.assertEquals(included.Id, (Id) scope[0].get('Id'));

    batch.execute(null, scope);
    batch.execute(null, scope);

    List<Catalog_Delta_Work_Item__c> items = [
      SELECT Product__c, IsImpacted__c
      FROM Catalog_Delta_Work_Item__c
      WHERE Run__c = :run.Id
    ];
    System.assertEquals(1, items.size(), 'Repeated discovery must be idempotent.');
    System.assertEquals(included.Id, items[0].Product__c);
    System.assertEquals(true, items[0].IsImpacted__c);
  }

  @IsTest
  static void testPriceDiscoveryUsesCapturedPricebookScopeAndDeduplicatesProducts() {
    Product2 product = createProduct('PRICE-63', 'Hardware');
    Pricebook2 selected = new Pricebook2(Name = 'Selected 63', IsActive = true);
    Pricebook2 ignored = new Pricebook2(Name = 'Ignored 63', IsActive = true);
    insert new List<Pricebook2>{ selected, ignored };
    insert new List<PricebookEntry>{
      new PricebookEntry(
        Pricebook2Id = Test.getStandardPricebookId(),
        Product2Id = product.Id,
        UnitPrice = 10,
        IsActive = true
      ),
      new PricebookEntry(
        Pricebook2Id = selected.Id,
        Product2Id = product.Id,
        UnitPrice = 11,
        IsActive = true
      ),
      new PricebookEntry(
        Pricebook2Id = ignored.Id,
        Product2Id = product.Id,
        UnitPrice = 12,
        IsActive = true
      )
    };

    CatalogJobConfig__mdt config = createConfig(
      'DELTA_PRICE_SCOPE_63',
      CatalogSyncMode.DELTA
    );
    config.PricebookIds__c = selected.Id;
    Catalog_Delta_Run__c run = createRun(
      config,
      CatalogDeltaStageBatch.DISCOVER_PRICES
    );
    run.PricebookScopeFiltered__c = true;
    run.ResolvedPricebookIdsJson__c = JSON.serialize(
      new List<String>{ String.valueOf(selected.Id) }
    );
    update run;

    CatalogDeltaStageBatch batch = new CatalogDeltaStageBatch(
      run.Id,
      CatalogDeltaStageBatch.DISCOVER_PRICES,
      0,
      config
    );
    List<SObject> scope = collectScope(batch.start(null));
    System.assertEquals(
      2,
      scope.size(),
      'Standard and the captured selected Pricebook should be scanned.'
    );
    batch.execute(null, scope);

    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Catalog_Delta_Work_Item__c
        WHERE Run__c = :run.Id AND IsImpacted__c = TRUE
      ],
      'Multiple relevant price entries must deduplicate to one product.'
    );
  }

  @IsTest
  static void testCategoryExpansionAndFanOutRemainQueryLocatorDriven() {
    Product2 product = createProduct('CATEGORY-63', 'Hardware');
    ProductCatalog catalog = new ProductCatalog(Name = 'Category Catalog 63');
    insert catalog;
    ProductCategory root = new ProductCategory(
      Name = 'Root 63',
      CatalogId = catalog.Id
    );
    insert root;
    ProductCategory child = new ProductCategory(
      Name = 'Child 63',
      CatalogId = catalog.Id,
      ParentCategoryId = root.Id
    );
    insert child;
    insert new ProductCategoryProduct(
      ProductId = product.Id,
      ProductCategoryId = child.Id
    );

    CatalogJobConfig__mdt config = createConfig(
      'DELTA_CATEGORY_63',
      CatalogSyncMode.DELTA
    );
    config.CatalogId__c = catalog.Id;
    Catalog_Delta_Run__c run = createRun(
      config,
      CatalogDeltaStageBatch.EXPAND_CATEGORIES
    );
    insert new Catalog_Delta_Work_Item__c(
      Run__c = run.Id,
      DedupeKey__c = run.Id + '|C|' + root.Id,
      Kind__c = 'Category',
      ProductCategory__c = root.Id,
      TraversalDepth__c = 0
    );

    CatalogDeltaStageBatch expansion = new CatalogDeltaStageBatch(
      run.Id,
      CatalogDeltaStageBatch.EXPAND_CATEGORIES,
      0,
      config
    );
    List<SObject> childScope = collectScope(expansion.start(null));
    System.assertEquals(1, childScope.size());
    expansion.execute(null, childScope);

    run.Stage__c = CatalogDeltaStageBatch.FAN_OUT_CATEGORY_PRODUCTS;
    update run;
    CatalogDeltaStageBatch fanOut = new CatalogDeltaStageBatch(
      run.Id,
      CatalogDeltaStageBatch.FAN_OUT_CATEGORY_PRODUCTS,
      0,
      config
    );
    List<SObject> assignmentScope = collectScope(fanOut.start(null));
    System.assertEquals(1, assignmentScope.size());
    fanOut.execute(null, assignmentScope);

    Catalog_Delta_Work_Item__c productItem = [
      SELECT Product__c, IsImpacted__c
      FROM Catalog_Delta_Work_Item__c
      WHERE Run__c = :run.Id AND Kind__c = 'Product'
      LIMIT 1
    ];
    System.assertEquals(product.Id, productItem.Product__c);
    System.assertEquals(true, productItem.IsImpacted__c);
  }

  @IsTest
  static void testRootResolutionFeedsRunScopedExportLocator() {
    Product2 product = createProduct('ROOT-63', 'Hardware');
    CatalogJobConfig__mdt config = createConfig(
      'DELTA_ROOT_63',
      CatalogSyncMode.DELTA
    );
    Catalog_Delta_Run__c run = createRun(
      config,
      CatalogDeltaStageBatch.RESOLVE_ROOTS
    );
    insert new Catalog_Delta_Work_Item__c(
      Run__c = run.Id,
      DedupeKey__c = run.Id + '|P|' + product.Id,
      Kind__c = 'Product',
      Product__c = product.Id,
      IsImpacted__c = true
    );

    CatalogDeltaStageBatch roots = new CatalogDeltaStageBatch(
      run.Id,
      CatalogDeltaStageBatch.RESOLVE_ROOTS,
      0,
      config
    );
    List<SObject> rootScope = collectScope(roots.start(null));
    roots.execute(null, rootScope);

    Catalog_Delta_Work_Item__c item = [
      SELECT IsRoot__c, IsExportCandidate__c, TraversalDepth__c
      FROM Catalog_Delta_Work_Item__c
      WHERE Run__c = :run.Id AND Product__c = :product.Id
    ];
    System.assertEquals(true, item.IsRoot__c);
    System.assertEquals(true, item.IsExportCandidate__c);
    System.assertEquals(0, item.TraversalDepth__c);

    List<SObject> exportScope = collectScope(
      CatalogJobScopeUtil.buildProductQueryLocatorForDeltaRun(
        config,
        run.Id,
        new List<String>{ 'Id', 'ProductCode' },
        null
      )
    );
    System.assertEquals(1, exportScope.size());
    System.assertEquals(product.Id, (Id) exportScope[0].get('Id'));
  }

  @IsTest
  static void testLaunchPersistsStableRunAndRejectsOverlap() {
    CatalogJobConfig__mdt fullConfig = createConfig(
      'FULL_63',
      CatalogSyncMode.FULL
    );
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_LAUNCH_63',
      CatalogSyncMode.DELTA
    );
    Datetime baseline = System.now().addMinutes(-10);
    CatalogSyncStateService.recordSuccessfulFullSync(fullConfig, baseline);

    Test.startTest();
    CatalogDeltaRunService.LaunchResult launch = CatalogDeltaRunService.launch(
      deltaConfig,
      baseline,
      System.now().addMinutes(1)
    );
    Boolean overlapRejected = false;
    try {
      CatalogDeltaRunService.launch(
        deltaConfig,
        baseline,
        System.now().addMinutes(2)
      );
    } catch (CatalogJobConfigException e) {
      overlapRejected = e.getMessage().contains('already running');
    }
    Boolean fullOverlapRejected = false;
    try {
      CatalogDeltaRunService.assertNoActiveDeltaRun(fullConfig);
    } catch (CatalogJobConfigException e) {
      fullOverlapRejected = e.getMessage().contains('already running');
    }
    Test.stopTest();

    System.assertNotEquals(null, launch.runId);
    System.assertNotEquals(null, launch.jobId);
    System.assertEquals(true, overlapRejected);
    System.assertEquals(true, fullOverlapRejected);

    Catalog_Sync_State__c stateRecord = [
      SELECT CurrentProductRun__c, CurrentProductRunMode__c
      FROM Catalog_Sync_State__c
      WHERE ResolvedTargetKey__c = :CatalogSyncStateService.buildResolvedTargetKey(
        deltaConfig
      )
    ];
    System.assertEquals(launch.runId, stateRecord.CurrentProductRun__c);
    System.assertEquals(CatalogSyncMode.DELTA, stateRecord.CurrentProductRunMode__c);
  }

  @IsTest
  static void testCompletionAdvancesWatermarkAndExposesRunSnapshot() {
    CatalogJobConfig__mdt fullConfig = createConfig(
      'FULL_63',
      CatalogSyncMode.FULL
    );
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_COMPLETE_63',
      CatalogSyncMode.DELTA
    );
    Datetime baseline = System.now().addHours(-2);
    Datetime cutoff = System.now().addHours(-1);
    CatalogSyncStateService.recordSuccessfulFullSync(fullConfig, baseline);
    Catalog_Delta_Run__c run = createRun(
      deltaConfig,
      CatalogDeltaStageBatch.EXPORT_PRODUCTS
    );
    run.BaselineTimestamp__c = baseline;
    run.CutoffTimestamp__c = cutoff;
    run.InitialAsyncJobId__c = UserInfo.getUserId();
    run.ImpactedProductCount__c = 3;
    run.RootProductCount__c = 2;
    update run;

    CatalogDeltaRunService.completeRun(run.Id, deltaConfig, 5);

    Catalog_Delta_Run__c completed = CatalogDeltaRunService.loadRun(run.Id);
    System.assertEquals(CatalogDeltaRunService.STATUS_SUCCEEDED, completed.Status__c);
    System.assertEquals(5, completed.ExportProductCount__c);
    Catalog_Sync_State__c stateRecord = [
      SELECT LastSuccessfulSyncAt__c, CurrentProductRun__c
      FROM Catalog_Sync_State__c
      WHERE ResolvedTargetKey__c = :run.ResolvedTargetKey__c
    ];
    System.assertEquals(cutoff, stateRecord.LastSuccessfulSyncAt__c);
    System.assertEquals(run.Id, stateRecord.CurrentProductRun__c);

    List<CatalogDeltaRunService.Snapshot> snapshots = CatalogDeltaRunService.getSnapshots(
      new List<String>{ String.valueOf(run.Id) }
    );
    System.assertEquals(1, snapshots.size());
    System.assertEquals('Completed', snapshots[0].status);
    System.assertEquals(true, snapshots[0].isTerminal);
    System.assert(snapshots[0].scopeSummary.contains('5 products exported'));
  }

  @IsTest
  static void testFailureDoesNotAdvanceWatermarkAndCleanupIsBounded() {
    CatalogJobConfig__mdt fullConfig = createConfig(
      'FULL_63',
      CatalogSyncMode.FULL
    );
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_FAILURE_63',
      CatalogSyncMode.DELTA
    );
    Datetime baseline = System.now().addHours(-2);
    CatalogSyncStateService.recordSuccessfulFullSync(fullConfig, baseline);
    Product2 product = createProduct('CLEANUP-63', 'Hardware');
    Catalog_Delta_Run__c run = createRun(
      deltaConfig,
      CatalogDeltaStageBatch.DISCOVER_PRICES
    );
    insert new Catalog_Delta_Work_Item__c(
      Run__c = run.Id,
      DedupeKey__c = run.Id + '|P|' + product.Id,
      Kind__c = 'Product',
      Product__c = product.Id,
      IsImpacted__c = true
    );

    CatalogDeltaRunService.suppressChainingInTests = false;
    Test.startTest();
    CatalogDeltaRunService.failRun(run.Id, 'Expected stage failure');
    Test.stopTest();
    Catalog_Sync_State__c stateAfterFailure = [
      SELECT LastSuccessfulSyncAt__c
      FROM Catalog_Sync_State__c
      WHERE ResolvedTargetKey__c = :run.ResolvedTargetKey__c
    ];
    System.assertEquals(baseline, stateAfterFailure.LastSuccessfulSyncAt__c);

    System.assertEquals(
      0,
      [SELECT COUNT() FROM Catalog_Delta_Work_Item__c WHERE Run__c = :run.Id]
    );
    System.assertEquals(
      CatalogDeltaRunService.CLEANUP_COMPLETED,
      [SELECT CleanupStatus__c FROM Catalog_Delta_Run__c WHERE Id = :run.Id]
        .CleanupStatus__c
    );
  }

  @IsTest
  static void testSnapshotReconcilesOrphanedRunWithoutAdvancingWatermark() {
    CatalogJobConfig__mdt fullConfig = createConfig(
      'FULL_63',
      CatalogSyncMode.FULL
    );
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_ORPHAN_63',
      CatalogSyncMode.DELTA
    );
    Datetime baseline = System.now().addHours(-2);
    CatalogSyncStateService.recordSuccessfulFullSync(fullConfig, baseline);
    Catalog_Delta_Run__c run = createRun(
      deltaConfig,
      CatalogDeltaStageBatch.DISCOVER_PRODUCTS
    );
    run.CurrentAsyncJobId__c = UserInfo.getUserId();
    update run;

    List<CatalogDeltaRunService.Snapshot> snapshots = CatalogDeltaRunService.getSnapshots(
      new List<String>{ String.valueOf(run.Id) }
    );

    System.assertEquals(1, snapshots.size());
    System.assertEquals('Failed', snapshots[0].status);
    System.assertEquals(true, snapshots[0].isTerminal);
    System.assertEquals(
      CatalogDeltaRunService.STATUS_FAILED,
      [SELECT Status__c FROM Catalog_Delta_Run__c WHERE Id = :run.Id].Status__c
    );
    System.assertEquals(
      baseline,
      [
        SELECT LastSuccessfulSyncAt__c
        FROM Catalog_Sync_State__c
        WHERE ResolvedTargetKey__c = :run.ResolvedTargetKey__c
      ].LastSuccessfulSyncAt__c
    );
  }

  @IsTest
  static void testCancellationWaitsForChildJobThenBecomesTerminal() {
    CatalogJobConfig__mdt config = createConfig(
      'DELTA_CANCEL_63',
      CatalogSyncMode.DELTA
    );
    Catalog_Delta_Run__c run = createRun(
      config,
      CatalogDeltaStageBatch.DISCOVER_PRODUCTS
    );

    Test.startTest();
    Id jobId = System.enqueueJob(new NoOpQueueable());
    run.CurrentAsyncJobId__c = String.valueOf(jobId);
    update run;
    CatalogDeltaRunService.cancelRun(run.Id);
    Test.stopTest();

    List<CatalogDeltaRunService.Snapshot> snapshots = CatalogDeltaRunService.getSnapshots(
      new List<String>{ String.valueOf(run.Id) }
    );
    System.assertEquals(1, snapshots.size());
    System.assertEquals('Aborted', snapshots[0].status);
    System.assertEquals(true, snapshots[0].isTerminal);
    System.assertEquals(
      CatalogDeltaRunService.STATUS_CANCELED,
      [SELECT Status__c FROM Catalog_Delta_Run__c WHERE Id = :run.Id].Status__c
    );
  }

  @IsTest
  static void testOutOfOrderCompletionCannotRegressWatermark() {
    CatalogJobConfig__mdt fullConfig = createConfig(
      'FULL_63',
      CatalogSyncMode.FULL
    );
    CatalogJobConfig__mdt deltaConfig = createConfig(
      'DELTA_OLDER_63',
      CatalogSyncMode.DELTA
    );
    Datetime newerWatermark = System.now().addMinutes(-10);
    CatalogSyncStateService.recordSuccessfulFullSync(fullConfig, newerWatermark);
    Catalog_Delta_Run__c run = createRun(
      deltaConfig,
      CatalogDeltaStageBatch.EXPORT_PRODUCTS
    );
    run.BaselineTimestamp__c = System.now().addHours(-3);
    run.CutoffTimestamp__c = System.now().addHours(-2);
    update run;

    CatalogDeltaRunService.completeRun(run.Id, deltaConfig, 0);

    System.assertEquals(
      newerWatermark,
      [
        SELECT LastSuccessfulSyncAt__c
        FROM Catalog_Sync_State__c
        WHERE ResolvedTargetKey__c = :run.ResolvedTargetKey__c
      ].LastSuccessfulSyncAt__c
    );
  }

  @IsTest
  static void testRunServiceValidationAndSnapshotHelpers() {
    Datetime nowValue = System.now();
    Boolean missingConfigRejected = false;
    try {
      CatalogDeltaRunService.launch(
        null,
        nowValue.addMinutes(-1),
        nowValue
      );
    } catch (CatalogJobConfigException e) {
      missingConfigRejected = e.getMessage().contains('Delta');
    }
    System.assertEquals(true, missingConfigRejected);

    CatalogJobConfig__mdt config = createConfig(
      'DELTA_HELPERS_63',
      CatalogSyncMode.DELTA
    );
    Boolean invalidWindowRejected = false;
    try {
      CatalogDeltaRunService.launch(config, nowValue, nowValue);
    } catch (CatalogJobConfigException e) {
      invalidWindowRejected = e.getMessage().contains('forward interval');
    }
    System.assertEquals(true, invalidWindowRejected);

    CatalogDeltaRunService.assertNoActiveDeltaRun(null);
    CatalogDeltaRunService.claimFullRun(null, null);
    System.assertEquals(
      0,
      CatalogDeltaRunService.getSnapshots(
        new List<String>{ null, '', 'not-a-run-id' }
      ).size()
    );
    System.assertEquals(
      true,
      CatalogDeltaRunService.isTerminalStatus(
        CatalogDeltaRunService.STATUS_SUCCEEDED
      )
    );
    System.assertEquals(
      true,
      CatalogDeltaRunService.isTerminalStatus(
        CatalogDeltaRunService.STATUS_FAILED
      )
    );
    System.assertEquals(
      true,
      CatalogDeltaRunService.isTerminalStatus(
        CatalogDeltaRunService.STATUS_CANCELED
      )
    );
    System.assertEquals(
      false,
      CatalogDeltaRunService.isTerminalStatus(
        CatalogDeltaRunService.STATUS_RUNNING
      )
    );

    Catalog_Delta_Run__c run = createRun(
      config,
      CatalogDeltaStageBatch.DISCOVER_PRICES
    );
    Id pricebookId = Test.getStandardPricebookId();
    run.PricebookScopeFiltered__c = true;
    run.ResolvedPricebookIdsJson__c = JSON.serialize(
      new List<String>{ String.valueOf(pricebookId) }
    );
    run.PricebookLabelsJson__c = JSON.serialize(
      new Map<String, String>{ String.valueOf(pricebookId) => 'standard' }
    );
    System.assertEquals(
      new Set<Id>{ pricebookId },
      CatalogDeltaRunService.getResolvedPricebookIds(run)
    );
    System.assertEquals(
      'standard',
      CatalogDeltaRunService.getPricebookLabels(run).get(pricebookId)
    );
    System.assertEquals(
      null,
      CatalogDeltaRunService.getResolvedPricebookIds(null)
    );
    System.assertEquals(0, CatalogDeltaRunService.getPricebookLabels(null).size());

    List<String> stages = new List<String>{
      CatalogDeltaStageBatch.DISCOVER_PRODUCTS,
      CatalogDeltaStageBatch.DISCOVER_PRICES,
      CatalogDeltaStageBatch.DISCOVER_ASSIGNMENTS,
      CatalogDeltaStageBatch.DISCOVER_CATEGORIES,
      CatalogDeltaStageBatch.EXPAND_CATEGORIES,
      CatalogDeltaStageBatch.FAN_OUT_CATEGORY_PRODUCTS,
      CatalogDeltaStageBatch.RESOLVE_ROOTS,
      CatalogDeltaStageBatch.EXPAND_GROUP_MEMBERS,
      CatalogDeltaStageBatch.EXPAND_CHILDREN,
      CatalogDeltaStageBatch.EXPORT_PRODUCTS,
      'FUTURE_STAGE'
    };
    for (String stage : stages) {
      System.assertNotEquals(null, CatalogDeltaRunService.describeStage(stage));
    }
    System.assertEquals(
      'Preparing delta sync',
      CatalogDeltaRunService.describeStage(null)
    );
  }
}
