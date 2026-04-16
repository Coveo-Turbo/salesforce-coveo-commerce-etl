@IsTest
private class DeltaProductCatalogExportBatchTest {
  private static List<HttpRequest> recordedRequests = new List<HttpRequest>();

  private class StubBatchableContext implements Database.BatchableContext {
    private Id jobId;

    StubBatchableContext(Id jobId) {
      this.jobId = jobId;
    }

    public Id getJobId() {
      return jobId;
    }

    public Id getChildJobId() {
      return null;
    }
  }

  private class MockResponse {
    Integer statusCode;
    String status;
    String body;

    MockResponse(Integer statusCode, String status, String body) {
      this.statusCode = statusCode;
      this.status = status;
      this.body = body;
    }
  }

  private class RecordingHttpMock implements HttpCalloutMock {
    private Map<String, MockResponse> responsesByToken;

    RecordingHttpMock(Map<String, MockResponse> responsesByToken) {
      this.responsesByToken = responsesByToken;
    }

    public HttpResponse respond(HttpRequest req) {
      recordedRequests.add(req);

      for (String token : responsesByToken.keySet()) {
        if (req.getEndpoint().contains(token)) {
          MockResponse config = responsesByToken.get(token);
          HttpResponse response = new HttpResponse();
          response.setStatusCode(config.statusCode);
          response.setStatus(config.status);
          response.setBody(config.body);
          return response;
        }
      }

      HttpResponse fallback = new HttpResponse();
      fallback.setStatusCode(500);
      fallback.setStatus('500 Missing Mock');
      fallback.setBody('No mock configured for endpoint: ' + req.getEndpoint());
      return fallback;
    }
  }

  private static Product2 createProduct(String code) {
    Product2 product = new Product2(
      Name = 'Delta ' + code,
      ProductCode = code,
      Description = 'Description ' + code,
      Family = 'Hardware',
      IsActive = true
    );
    insert product;

    insert new PricebookEntry(
      Pricebook2Id = Test.getStandardPricebookId(),
      Product2Id = product.Id,
      UnitPrice = 19.95,
      IsActive = true
    );

    return product;
  }

  private static CatalogJobConfig__mdt createConfig() {
    return new CatalogJobConfig__mdt(
      DeveloperName = 'DELTA_JOB',
      MasterLabel = 'Delta Job',
      CoveoOrgId__c = 'org-123',
      SourceId__c = 'source-456',
      Locale__c = 'en-US',
      BuilderType__c = 'Default',
      AdditionalProductFields__c = 'Description',
      BatchSize__c = 20,
      SyncMode__c = 'Delta',
      BaselineFullConfigDeveloperName__c = 'FULL_JOB'
    );
  }

  private static List<Product2> collectProducts(Database.QueryLocator locator) {
    List<Product2> products = new List<Product2>();
    Database.QueryLocatorIterator iterator = locator.iterator();
    while (iterator.hasNext()) {
      products.add((Product2) iterator.next());
    }
    return products;
  }

  @TestSetup
  static void clearOverrides() {
    DeltaProductCatalogExportBatch.testJobConfigOverride = null;
    CatalogSyncStateService.clearTestOverrides();
  }

  @IsTest
  static void testStart_returnsChangedProductsSinceBaseline() {
    Product2 product = createProduct('START-001');
    CatalogJobConfig__mdt config = createConfig();
    DeltaProductCatalogExportBatch batch = new DeltaProductCatalogExportBatch(
      config,
      Test.getStandardPricebookId(),
      System.now().addMinutes(-5)
    );

    List<Product2> scopeProducts = collectProducts(batch.start(null));

    System.assertEquals(1, scopeProducts.size());
    System.assertEquals(product.Id, scopeProducts[0].Id);
  }

  @IsTest
  static void testExecuteAndFinish_recordsDeltaStateWithoutDeleteOlderThan() {
    recordedRequests.clear();
    Product2 product = createProduct('EXEC-001');
    Product2 scopedProduct = [
      SELECT Id, Name, ProductCode, Description, Family, IsActive
      FROM Product2
      WHERE Id = :product.Id
    ];

    CatalogJobConfig__mdt config = createConfig();
    DeltaProductCatalogExportBatch batch = new DeltaProductCatalogExportBatch(
      config,
      Test.getStandardPricebookId(),
      System.now().addMinutes(-5)
    );
    batch.runCutoff = System.now();

    Test.setMock(
      HttpCalloutMock.class,
      new RecordingHttpMock(
        new Map<String, MockResponse>{
          '/files' => new MockResponse(
            201,
            '201 Created',
            '{"fileId":"delta-file","uploadUri":"https://upload.example.com/put","requiredHeaders":{"x-amz-meta-test":"abc"}}'
          ),
          '/stream/update' => new MockResponse(
            202,
            '202 Accepted',
            '{"orderingId":91}'
          ),
          'upload.example.com/put' => new MockResponse(200, '200 OK', '')
        }
      )
    );

    Test.startTest();
    batch.execute(null, new List<Product2>{ scopedProduct });
    batch.finish(null);
    Test.stopTest();

    System.assertEquals(3, recordedRequests.size());
    for (HttpRequest request : recordedRequests) {
      System.assert(!request.getEndpoint().contains('/deleteolderthan/'));
    }

    Catalog_Sync_State__c stateRecord = [
      SELECT
        BaselineFullConfigDeveloperName__c,
        LastSuccessfulSyncAt__c,
        LastRunMode__c,
        LastSuccessfulConfigDeveloperName__c
      FROM Catalog_Sync_State__c
      WHERE ResolvedTargetKey__c = :CatalogSyncStateService.buildResolvedTargetKey(
        config
      )
      LIMIT 1
    ];

    System.assertEquals('FULL_JOB', stateRecord.BaselineFullConfigDeveloperName__c);
    System.assertEquals(CatalogSyncMode.DELTA, stateRecord.LastRunMode__c);
    System.assertEquals('DELTA_JOB', stateRecord.LastSuccessfulConfigDeveloperName__c);
    System.assertNotEquals(null, stateRecord.LastSuccessfulSyncAt__c);
  }

  @IsTest
  static void testPublicConstructor_loadsConfigFromTestOverride() {
    Test.getStandardPricebookId();
    DeltaProductCatalogExportBatch.testJobConfigOverride = createConfig();

    DeltaProductCatalogExportBatch batch = new DeltaProductCatalogExportBatch(
      'DELTA_JOB'
    );

    System.assertEquals(20, batch.getBatchSize());
  }

  @IsTest
  static void testGetBatchSize_defaultsToFiftyWhenUnset() {
    CatalogJobConfig__mdt config = createConfig();
    config.BatchSize__c = null;

    DeltaProductCatalogExportBatch batch = new DeltaProductCatalogExportBatch(
      config,
      Test.getStandardPricebookId(),
      System.now().addMinutes(-5)
    );

    System.assertEquals(50, batch.getBatchSize());
  }

  @IsTest
  static void testStart_loadsBaselineFromReadinessStateWhenUnset() {
    Product2 product = createProduct('READY-001');
    CatalogJobConfig__mdt deltaConfig = createConfig();
    CatalogJobConfig__mdt fullConfig = createConfig();
    fullConfig.DeveloperName = 'FULL_JOB';
    fullConfig.MasterLabel = 'Full Job';
    fullConfig.SyncMode__c = CatalogSyncMode.FULL;
    fullConfig.BaselineFullConfigDeveloperName__c = null;
    Datetime baseline = System.now().addMinutes(-10);

    CatalogSyncStateService.testConfigsByDeveloperName =
      new Map<String, CatalogJobConfig__mdt>{ 'FULL_JOB' => fullConfig };
    CatalogSyncStateService.testStatesByTargetKey =
      new Map<String, Catalog_Sync_State__c>{
        CatalogSyncStateService.buildResolvedTargetKey(deltaConfig) =>
          new Catalog_Sync_State__c(
            ResolvedTargetKey__c = CatalogSyncStateService.buildResolvedTargetKey(
              deltaConfig
            ),
            BaselineFullConfigDeveloperName__c = 'FULL_JOB',
            LastSuccessfulFullSyncAt__c = baseline,
            LastSuccessfulSyncAt__c = baseline
          )
      };

    DeltaProductCatalogExportBatch batch = new DeltaProductCatalogExportBatch(
      deltaConfig,
      Test.getStandardPricebookId(),
      null
    );

    List<Product2> scopeProducts = collectProducts(batch.start(null));

    System.assertEquals(baseline, batch.baselineTimestamp);
    System.assertEquals(1, scopeProducts.size());
    System.assertEquals(product.Id, scopeProducts[0].Id);
    System.assertNotEquals(null, batch.runCutoff);
  }

  @IsTest
  static void testConstructorRejectsNullConfig() {
    try {
      new DeltaProductCatalogExportBatch(
        (CatalogJobConfig__mdt) null,
        Test.getStandardPricebookId(),
        null
      );
      System.assert(false, 'Expected CatalogJobException');
    } catch (CatalogJobException e) {
      System.assert(e.getMessage().contains('Catalog job config is required'));
    }
  }

  @IsTest
  static void testConstructorRejectsNonDeltaConfig() {
    CatalogJobConfig__mdt config = createConfig();
    config.SyncMode__c = CatalogSyncMode.FULL;

    try {
      new DeltaProductCatalogExportBatch(
        config,
        Test.getStandardPricebookId(),
        null
      );
      System.assert(false, 'Expected CatalogJobConfigException');
    } catch (CatalogJobConfigException e) {
      System.assert(e.getMessage().contains('requires SyncMode__c = Delta'));
    }
  }

  @IsTest
  static void testFinishSkipsStateUpdateWhenBatchDidNotComplete() {
    CatalogJobConfig__mdt config = createConfig();
    DeltaProductCatalogExportBatch batch = new DeltaProductCatalogExportBatch(
      config,
      Test.getStandardPricebookId(),
      System.now().addMinutes(-5)
    );
    batch.runCutoff = System.now();

    batch.finish(new StubBatchableContext('707000000000000AAA'));

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Catalog_Sync_State__c
        WHERE ResolvedTargetKey__c = :CatalogSyncStateService.buildResolvedTargetKey(
          config
        )
      ]
    );
  }
}
