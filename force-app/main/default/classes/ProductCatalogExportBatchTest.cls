@IsTest
private class ProductCatalogExportBatchTest {
  private static List<HttpRequest> recordedRequests = new List<HttpRequest>();

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
          HttpResponse res = new HttpResponse();
          res.setStatusCode(config.statusCode);
          res.setStatus(config.status);
          res.setBody(config.body);
          return res;
        }
      }

      HttpResponse fallback = new HttpResponse();
      fallback.setStatusCode(500);
      fallback.setStatus('500 Missing Mock');
      fallback.setBody('No mock configured for endpoint: ' + req.getEndpoint());
      return fallback;
    }
  }

  private static Product2 createTestProduct(String code, String family) {
    Product2 product = new Product2(
      Name = 'Batch Test ' + code,
      ProductCode = code,
      Description = 'Description for ' + code,
      Family = family,
      IsActive = true
    );
    insert product;

    insert new PricebookEntry(
      Pricebook2Id = Test.getStandardPricebookId(),
      Product2Id = product.Id,
      UnitPrice = 42.50,
      IsActive = true
    );

    return product;
  }

  private static CatalogJobConfig__mdt createConfig(
    String builderType,
    Boolean enablePayloadLogging
  ) {
    return new CatalogJobConfig__mdt(
      DeveloperName = 'UnitTestConfig',
      MasterLabel = 'Unit Test Config',
      CoveoOrgId__c = 'org-123',
      SourceId__c = 'source-456',
      Locale__c = 'en',
      IsActive__c = true,
      BuilderType__c = builderType,
      AdditionalProductFields__c = 'Description, Family, Description',
      BatchSize__c = 25,
      EnablePayloadLogging__c = enablePayloadLogging
    );
  }

  private static ProductCatalog createCatalogHierarchy(Product2 product) {
    ProductCatalog catalog = new ProductCatalog(Name = 'Batch Test Catalog');
    insert catalog;

    ProductCategory rootCategory = new ProductCategory(
      Name = 'Root Category',
      CatalogId = catalog.Id
    );
    insert rootCategory;

    ProductCategory childCategory = new ProductCategory(
      Name = 'Child Category',
      CatalogId = catalog.Id,
      ParentCategoryId = rootCategory.Id
    );
    insert childCategory;

    insert new ProductCategoryProduct(
      ProductId = product.Id,
      ProductCategoryId = childCategory.Id
    );

    return catalog;
  }

  private static List<Product2> collectProducts(Database.QueryLocator locator) {
    List<Product2> products = new List<Product2>();
    Database.QueryLocatorIterator iterator = locator.iterator();
    while (iterator.hasNext()) {
      products.add((Product2) iterator.next());
    }
    return products;
  }

  @IsTest
  static void testGetBatchSize_usesConfiguredValueAndDefault() {
    CatalogJobConfig__mdt configured = createConfig('Default', false);
    ProductCatalogExportBatch configuredBatch = new ProductCatalogExportBatch(
      configured,
      Test.getStandardPricebookId()
    );
    System.assertEquals(25, configuredBatch.getBatchSize());

    CatalogJobConfig__mdt fallback = createConfig('Default', false);
    fallback.BatchSize__c = null;
    ProductCatalogExportBatch fallbackBatch = new ProductCatalogExportBatch(
      fallback,
      Test.getStandardPricebookId()
    );
    System.assertEquals(50, fallbackBatch.getBatchSize());
  }

  @IsTest
  static void testGetProductIdsForCatalog_returnsLinkedProducts() {
    Product2 linkedProduct = createTestProduct('CAT-001', 'Hardware');
    Product2 unlinkedProduct = createTestProduct('CAT-002', 'Hardware');
    ProductCatalog catalog = createCatalogHierarchy(linkedProduct);

    Set<Id> productIds = ProductCatalogExportBatch.getProductIdsForCatalog(
      catalog.Id
    );

    System.assert(productIds.contains(linkedProduct.Id));
    System.assert(!productIds.contains(unlinkedProduct.Id));
  }

  @IsTest
  static void testValidateAndSanitizeFilter_allowsSimpleAndBlocksUnsafeQueries() {
    System.assertEquals(
      'Family = \'Hardware\'',
      ProductCatalogExportBatch.validateAndSanitizeFilter(
        '  Family = \'Hardware\'  '
      )
    );

    Boolean dmlBlocked = false;
    try {
      ProductCatalogExportBatch.validateAndSanitizeFilter(
        'Name != null UPDATE Account'
      );
    } catch (CatalogJobException e) {
      dmlBlocked = true;
      System.assert(e.getMessage().contains('DML keyword'));
    }
    System.assertEquals(true, dmlBlocked);

    Boolean subqueryBlocked = false;
    try {
      ProductCatalogExportBatch.validateAndSanitizeFilter(
        'Id IN (SELECT ProductId FROM ProductCategoryProduct)'
      );
    } catch (CatalogJobException e) {
      subqueryBlocked = true;
      System.assert(e.getMessage().contains('subquery pattern'));
    }
    System.assertEquals(true, subqueryBlocked);
  }

  @IsTest
  static void testStart_handlesCatalogFilterAndEmptyCatalog() {
    Product2 linkedProduct = createTestProduct('START-001', 'Hardware');
    ProductCatalog populatedCatalog = createCatalogHierarchy(linkedProduct);

    CatalogJobConfig__mdt populatedConfig = createConfig('Commerce', false);
    populatedConfig.CatalogId__c = populatedCatalog.Id;
    populatedConfig.ProductFilter__c = 'Family = \'Hardware\'';

    ProductCatalogExportBatch populatedBatch = new ProductCatalogExportBatch(
      populatedConfig,
      Test.getStandardPricebookId()
    );

    Database.QueryLocator populatedLocator = populatedBatch.start(null);

    System.assertNotEquals(null, populatedLocator);

    ProductCatalog emptyCatalog = new ProductCatalog(Name = 'Empty Catalog');
    insert emptyCatalog;

    CatalogJobConfig__mdt emptyConfig = createConfig('Commerce', false);
    emptyConfig.CatalogId__c = emptyCatalog.Id;

    ProductCatalogExportBatch emptyBatch = new ProductCatalogExportBatch(
      emptyConfig,
      Test.getStandardPricebookId()
    );

    Database.QueryLocator emptyLocator = emptyBatch.start(null);

    System.assertNotEquals(null, emptyLocator);
  }

  @IsTest
  static void testStart_rejectsUnsafeFilter() {
    CatalogJobConfig__mdt config = createConfig('Default', false);
    config.ProductFilter__c = 'Id IN (SELECT Id FROM Account)';

    ProductCatalogExportBatch batch = new ProductCatalogExportBatch(
      config,
      Test.getStandardPricebookId()
    );

    Boolean failed = false;
    try {
      batch.start(null);
    } catch (CatalogJobException e) {
      failed = true;
      System.assert(e.getMessage().contains('subquery pattern'));
    }

    System.assertEquals(true, failed);
  }

  @IsTest
  static void testStart_includesProviderRequiredIdentityFieldsInProductQuery() {
    recordedRequests.clear();
    createTestProduct('EXEC-ID-001', 'Hardware');

    CatalogJobConfig__mdt config = createConfig(
      'CatalogJsonBuilderCreatedByIdStub',
      true
    );
    ProductCatalogExportBatch batch = new ProductCatalogExportBatch(
      config,
      Test.getStandardPricebookId()
    );

    List<Product2> scopeProducts = collectProducts(batch.start(null));

    Test.setMock(
      HttpCalloutMock.class,
      new RecordingHttpMock(
        new Map<String, MockResponse>{
          '/files' => new MockResponse(
            201,
            '201 Created',
            '{"fileId":"file-createdby","uploadUri":"https://upload.example.com/put","requiredHeaders":{"x-amz-meta-test":"abc"}}'
          ),
          'upload.example.com' => new MockResponse(200, '200 OK', ''),
          '/stream/update' => new MockResponse(
            202,
            '202 Accepted',
            '{"orderingId":21,"streamId":"stream-createdby"}'
          )
        }
      )
    );

    Test.startTest();
    batch.execute(null, scopeProducts);
    Test.stopTest();

    List<Coveo_Payload_Log__c> logs = [
      SELECT Payload__c
      FROM Coveo_Payload_Log__c
    ];
    System.assertEquals(1, logs.size());
    System.assert(
      logs[0].Payload__c.contains(UserInfo.getUserId()),
      'The builder-specific identity field should be available in the queried scope records'
    );
  }

  @IsTest
  static void testExecute_captureOrderingIdAndInsertPayloadLog() {
    recordedRequests.clear();
    Product2 product = createTestProduct('EXEC-001', 'Hardware');
    Product2 scopedProduct = [
      SELECT Id, Name, ProductCode, Description, Family, IsActive
      FROM Product2
      WHERE Id = :product.Id
    ];

    CatalogJobConfig__mdt config = createConfig('Default', true);
    ProductCatalogExportBatch batch = new ProductCatalogExportBatch(
      config,
      Test.getStandardPricebookId()
    );

    Test.setMock(
      HttpCalloutMock.class,
      new RecordingHttpMock(
        new Map<String, MockResponse>{
          '/files' => new MockResponse(
            201,
            '201 Created',
            '{"fileId":"file-123","uploadUri":"https://upload.example.com/put","requiredHeaders":{"x-amz-meta-test":"abc"}}'
          ),
          'upload.example.com' => new MockResponse(200, '200 OK', ''),
          '/stream/update' => new MockResponse(
            202,
            '202 Accepted',
            '{"orderingId":42,"streamId":"stream-123"}'
          ),
          '/deleteolderthan/' => new MockResponse(
            200,
            '200 OK',
            '{"deletedCount":1}'
          )
        }
      )
    );

    Test.startTest();
    batch.execute(null, new List<Product2>{ scopedProduct });
    Test.stopTest();

    System.assertEquals(42L, batch.firstOrderingId);
    System.assertEquals(3, recordedRequests.size());
    System.assert(recordedRequests[0].getEndpoint().contains('/files'));
    System.assertEquals('abc', recordedRequests[1].getHeader('x-amz-meta-test'));
    System.assert(recordedRequests[2].getEndpoint().contains('/stream/update'));

    List<Coveo_Payload_Log__c> logs = [
      SELECT ScopeSize__c, OperationCount__c, IsValid__c, Reason__c, Payload__c
      FROM Coveo_Payload_Log__c
    ];
    System.assertEquals(1, logs.size());
    System.assertEquals(1, logs[0].ScopeSize__c.intValue());
    System.assertEquals(1, logs[0].OperationCount__c.intValue());
    System.assertEquals(true, logs[0].IsValid__c);
    System.assertEquals('OK', logs[0].Reason__c);
    System.assert(logs[0].Payload__c.contains('EXEC-001'));
    System.assert(logs[0].Payload__c.contains('sf_description'));
  }

  @IsTest
  static void testFinish_deletesOlderItemsWhenOrderingIdPresent() {
    recordedRequests.clear();
    CatalogJobConfig__mdt config = createConfig('Default', false);
    ProductCatalogExportBatch batch = new ProductCatalogExportBatch(
      config,
      Test.getStandardPricebookId()
    );
    batch.firstOrderingId = 84L;

    Test.setMock(
      HttpCalloutMock.class,
      new RecordingHttpMock(
        new Map<String, MockResponse>{
          '/deleteolderthan/' => new MockResponse(
            200,
            '200 OK',
            '{"deletedCount":2}'
          )
        }
      )
    );

    Test.startTest();
    batch.finish(null);
    Test.stopTest();

    System.assertEquals(1, recordedRequests.size());
    System.assert(
      recordedRequests[0].getEndpoint().contains('/deleteolderthan/84')
    );
    System.assertEquals('POST', recordedRequests[0].getMethod());
  }

  @IsTest
  static void testExecuteWithoutPayloadLogging_skipsLogInsert() {
    recordedRequests.clear();
    Product2 product = createTestProduct('EXEC-002', 'Hardware');
    Product2 scopedProduct = [
      SELECT Id, Name, ProductCode, Description, Family, IsActive
      FROM Product2
      WHERE Id = :product.Id
    ];

    CatalogJobConfig__mdt config = createConfig('Default', false);
    ProductCatalogExportBatch batch = new ProductCatalogExportBatch(
      config,
      Test.getStandardPricebookId()
    );

    Test.setMock(
      HttpCalloutMock.class,
      new RecordingHttpMock(
        new Map<String, MockResponse>{
          '/files' => new MockResponse(
            201,
            '201 Created',
            '{"fileId":"file-456","uploadUri":"https://upload.example.com/put","requiredHeaders":{"x-amz-meta-test":"abc"}}'
          ),
          'upload.example.com' => new MockResponse(200, '200 OK', ''),
          '/stream/update' => new MockResponse(
            202,
            '202 Accepted',
            '{"orderingId":84,"streamId":"stream-456"}'
          ),
          '/deleteolderthan/' => new MockResponse(
            200,
            '200 OK',
            '{"deletedCount":2}'
          )
        }
      )
    );

    Test.startTest();
    batch.execute(null, new List<Product2>{ scopedProduct });
    Test.stopTest();

    System.assertEquals(84L, batch.firstOrderingId);
    System.assertEquals(0, [SELECT COUNT() FROM Coveo_Payload_Log__c]);
  }
}
