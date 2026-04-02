@IsTest
private class EmbeddedBuyerGroupAccessExportBatchTest {
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
    private final Map<String, MockResponse> responsesByToken;

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

  private static CatalogJobConfig__mdt createConfig(String builderType) {
    return new CatalogJobConfig__mdt(
      DeveloperName = 'EmbeddedAccessTest',
      MasterLabel = 'Embedded Access Test',
      CoveoOrgId__c = 'org-embedded-test',
      SourceId__c = 'product-source-embedded',
      WebStoreId__c = '0ZE000000000001AAA',
      BuyerGroupAvailabilityMode__c =
        CatalogBuyerGroupAvailabilityMode.EMBEDDED,
      EnablePayloadLogging__c = true,
      BuilderType__c = builderType,
      BatchSize__c = 20
    );
  }

  private static Product2 createProduct(String code) {
    Product2 product = new Product2(
      Name = 'Embedded Access ' + code,
      ProductCode = code,
      Family = 'Hardware',
      IsActive = true
    );
    if (
      Product2.SObjectType
        .getDescribe()
        .fields.getMap()
        .containsKey('Item_Number__c')
    ) {
      product.put('Item_Number__c', code);
    }
    insert product;
    return product;
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
  static void testConstructorValidation_requiresEmbeddedModeAndWebStore() {
    Boolean modeFailureThrown = false;
    try {
      new EmbeddedBuyerGroupAccessExportBatch(
        new CatalogJobConfig__mdt(
          BuyerGroupAvailabilityMode__c =
            CatalogBuyerGroupAvailabilityMode.PAIRED_SOURCE,
          WebStoreId__c = '0ZE000000000001AAA'
        )
      );
    } catch (CatalogJobConfigException ex) {
      modeFailureThrown = true;
      System.assert(ex.getMessage().contains('Embedded or DualWrite'));
    }
    System.assertEquals(true, modeFailureThrown);

    Boolean webStoreFailureThrown = false;
    try {
      new EmbeddedBuyerGroupAccessExportBatch(
        new CatalogJobConfig__mdt(
          BuyerGroupAvailabilityMode__c =
            CatalogBuyerGroupAvailabilityMode.EMBEDDED
        )
      );
    } catch (CatalogJobConfigException ex) {
      webStoreFailureThrown = true;
      System.assert(ex.getMessage().contains('WebStoreId__c is required'));
    }
    System.assertEquals(true, webStoreFailureThrown);
  }

  @IsTest
  static void testExecute_buildsPartialUpdatePayloadWithBuilderIdentity() {
    recordedRequests.clear();
    createProduct('EMBED-501');

    CatalogJobConfig__mdt config = createConfig(
      'CatalogJsonBuilderCreatedByIdStub'
    );
    EmbeddedBuyerGroupAccessExportBatch batch =
      new EmbeddedBuyerGroupAccessExportBatch(config);
    List<Product2> scope = collectProducts(batch.start(null));

    Test.setMock(
      HttpCalloutMock.class,
      new RecordingHttpMock(
        new Map<String, MockResponse>{
          '/files' => new MockResponse(
            201,
            '201 Created',
            '{"fileId":"file-access","uploadUri":"https://upload.example.com/put","requiredHeaders":{"x-amz-meta-test":"abc"}}'
          ),
          'upload.example.com' => new MockResponse(200, '200 OK', ''),
          '/stream/update' => new MockResponse(
            202,
            '202 Accepted',
            '{"orderingId":77,"streamId":"stream-access"}'
          )
        }
      )
    );

    Test.startTest();
    batch.execute(null, scope);
    Test.stopTest();

    System.assertEquals(3, recordedRequests.size());

    List<Coveo_Payload_Log__c> logs = [
      SELECT ScopeSize__c, OperationCount__c, IsValid__c, Payload__c
      FROM Coveo_Payload_Log__c
    ];
    System.assertEquals(1, logs.size());
    System.assertEquals(1, logs[0].ScopeSize__c.intValue());
    System.assertEquals(
      3,
      logs[0].OperationCount__c.intValue(),
      'Embedded access sync should emit three field replace operations per product'
    );
    System.assertEquals(true, logs[0].IsValid__c);
    System.assert(
      logs[0].Payload__c.contains('"partialUpdate"'),
      'Embedded access syncs should upload partialUpdate payloads'
    );
    System.assert(
      logs[0].Payload__c.contains(
        '"documentId":"product://' + UserInfo.getUserId() + '"'
      ),
      'The batch should use the builder-driven ec_product_id when updating product access'
    );
    System.assert(
      logs[0].Payload__c.contains('"sf_webstore_id"'),
      'Embedded access payloads should replace the Web Store field'
    );
  }

  @IsTest
  static void testGetBatchSize_usesLargeMinimumAndCapsAtPlatformMaximum() {
    CatalogJobConfig__mdt belowMinimum = createConfig('CatalogJsonBuilderDefault');
    belowMinimum.BatchSize__c = 20;
    EmbeddedBuyerGroupAccessExportBatch normalizedBatch =
      new EmbeddedBuyerGroupAccessExportBatch(belowMinimum);
    System.assertEquals(
      EmbeddedBuyerGroupAccessExportBatch.DEFAULT_BATCH_SIZE,
      normalizedBatch.getBatchSize(),
      'Embedded access syncs should clamp small batch sizes upward to reduce Stream API burst throttling'
    );

    CatalogJobConfig__mdt aboveMaximum = createConfig('CatalogJsonBuilderDefault');
    aboveMaximum.BatchSize__c = 2500;
    EmbeddedBuyerGroupAccessExportBatch cappedBatch =
      new EmbeddedBuyerGroupAccessExportBatch(aboveMaximum);
    System.assertEquals(
      EmbeddedBuyerGroupAccessExportBatch.MAX_BATCH_SIZE,
      cappedBatch.getBatchSize(),
      'Embedded access syncs should respect the platform executeBatch maximum scope'
    );

    CatalogJobConfig__mdt defaultedConfig = createConfig('CatalogJsonBuilderDefault');
    defaultedConfig.BatchSize__c = null;
    EmbeddedBuyerGroupAccessExportBatch defaultedBatch =
      new EmbeddedBuyerGroupAccessExportBatch(defaultedConfig);
    System.assertEquals(
      EmbeddedBuyerGroupAccessExportBatch.DEFAULT_BATCH_SIZE,
      defaultedBatch.getBatchSize(),
      'Embedded access syncs should default to the larger throttling-safe scope'
    );
  }
}
