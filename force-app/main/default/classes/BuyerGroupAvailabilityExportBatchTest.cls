@IsTest
private class BuyerGroupAvailabilityExportBatchTest {
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

  private static CatalogJobConfig__mdt createConfig(Id webStoreId) {
    return new CatalogJobConfig__mdt(
      DeveloperName = 'BuyerGroupAvailabilityTest',
      MasterLabel = 'Buyer Group Availability Test',
      CoveoOrgId__c = 'org-availability-test',
      AvailabilitySourceId__c = 'availability-source-test',
      WebStoreId__c = String.valueOf(webStoreId),
      EnableBuyerGroupAvailability__c = true,
      EnablePayloadLogging__c = true,
      ProductFilter__c = 'Family = \'Hardware\'',
      BatchSize__c = 10
    );
  }

  private static WebStore createWebStore(String name) {
    WebStore store = new WebStore(
      Name = name,
      OptionsAutoFacetingEnabled = false,
      OptionsCartAsyncProcessingEnabled = false,
      OptionsCartCalculateEnabled = false,
      OptionsCartToOrderAutoCustomFieldMapping = false,
      OptionsCommerceEinsteinActivitiesTracked = false,
      OptionsCommerceEinsteinDeployed = false,
      OptionsDuplicateCartItemsEnabled = false,
      OptionsGuestBrowsingEnabled = false,
      OptionsGuestCartEnabled = false,
      OptionsGuestCheckoutEnabled = false,
      OptionsPreserveGuestCartEnabled = false,
      OptionsSkipAdditionalEntitlementCheckForSearch = false,
      OptionsSkuDetectionEnabled = false,
      OptionsSplitShipmentEnabled = false
    );
    insert store;
    return store;
  }

  private static SObject createBuyerGroup(String name) {
    SObject buyerGroup = Schema.getGlobalDescribe().get('BuyerGroup').newSObject();
    buyerGroup.put('Name', name);
    insert buyerGroup;
    return buyerGroup;
  }

  private static SObject createPolicy(
    String name,
    Boolean canViewProduct,
    Boolean canViewPrice
  ) {
    SObject policy = Schema.getGlobalDescribe()
      .get('CommerceEntitlementPolicy')
      .newSObject();
    policy.put('Name', name);
    policy.put('CanViewProduct', canViewProduct);
    policy.put('CanViewPrice', canViewPrice);
    insert policy;
    return policy;
  }

  private static void linkWebStoreBuyerGroup(Id webStoreId, Id buyerGroupId) {
    SObject link = Schema.getGlobalDescribe().get('WebStoreBuyerGroup').newSObject();
    link.put('WebStoreId', webStoreId);
    link.put('BuyerGroupId', buyerGroupId);
    insert link;
  }

  private static void linkPolicyBuyerGroup(Id policyId, Id buyerGroupId) {
    SObject link = Schema.getGlobalDescribe()
      .get('CommerceEntitlementBuyerGroup')
      .newSObject();
    link.put('PolicyId', policyId);
    link.put('BuyerGroupId', buyerGroupId);
    insert link;
  }

  private static void linkPolicyProduct(Id policyId, Id productId) {
    SObject link = Schema.getGlobalDescribe()
      .get('CommerceEntitlementProduct')
      .newSObject();
    link.put('PolicyId', policyId);
    link.put('ProductId', productId);
    insert link;
  }

  private static Product2 createProduct(String code, String family) {
    Product2 product = new Product2(
      Name = 'Availability Test ' + code,
      ProductCode = code,
      Family = family,
      IsActive = true
    );
    insert product;
    return product;
  }

  private static ProductCatalog createCatalogWithProducts(List<Product2> products) {
    ProductCatalog catalog = new ProductCatalog(Name = 'Availability Test Catalog');
    insert catalog;

    ProductCategory category = new ProductCategory(
      Name = 'Availability Test Category',
      CatalogId = catalog.Id
    );
    insert category;

    List<ProductCategoryProduct> links = new List<ProductCategoryProduct>();
    for (Product2 product : products) {
      links.add(
        new ProductCategoryProduct(
          ProductId = product.Id,
          ProductCategoryId = category.Id
        )
      );
    }
    insert links;

    return catalog;
  }

  private static List<SObject> queryBuyerGroups(Set<Id> buyerGroupIds) {
    return Database.query(
      'SELECT Id, Name FROM BuyerGroup WHERE Id IN :buyerGroupIds ORDER BY Name'
    );
  }

  private static List<String> readQueryLocatorNames(Database.QueryLocator locator) {
    List<String> names = new List<String>();
    Database.QueryLocatorIterator iterator = locator.iterator();
    while (iterator.hasNext()) {
      SObject nextRecord = iterator.next();
      names.add((String) nextRecord.get('Name'));
    }
    return names;
  }

  @IsTest
  static void testConstructorValidation_requiresEnabledAvailabilityAndFields() {
    WebStore store = createWebStore('Validation Store');

    CatalogJobConfig__mdt disabledConfig = createConfig(store.Id);
    disabledConfig.EnableBuyerGroupAvailability__c = false;
    assertConfigFailure(
      disabledConfig,
      'EnableBuyerGroupAvailability__c must be true'
    );

    CatalogJobConfig__mdt missingSourceConfig = createConfig(store.Id);
    missingSourceConfig.AvailabilitySourceId__c = null;
    assertConfigFailure(
      missingSourceConfig,
      'AvailabilitySourceId__c is required'
    );

    CatalogJobConfig__mdt missingStoreConfig = createConfig(store.Id);
    missingStoreConfig.WebStoreId__c = null;
    assertConfigFailure(missingStoreConfig, 'WebStoreId__c is required');
  }

  @IsTest
  static void testStart_returnsBuyerGroupsForConfiguredStore() {
    WebStore store = createWebStore('Availability Start Store');
    SObject alphaBuyerGroup = createBuyerGroup('Alpha Buyers');
    SObject betaBuyerGroup = createBuyerGroup('Beta Buyers');
    linkWebStoreBuyerGroup(store.Id, (Id) alphaBuyerGroup.get('Id'));
    linkWebStoreBuyerGroup(store.Id, (Id) betaBuyerGroup.get('Id'));

    BuyerGroupAvailabilityExportBatch batch =
      new BuyerGroupAvailabilityExportBatch(createConfig(store.Id));

    List<String> names = readQueryLocatorNames(batch.start(null));

    System.assertEquals(
      new List<String>{ 'Alpha Buyers', 'Beta Buyers' },
      names,
      'The start query should scope Buyer Groups to the configured store'
    );
  }

  @IsTest
  static void testStart_throwsWhenStoreHasNoBuyerGroups() {
    WebStore store = createWebStore('Empty Availability Store');

    Boolean exceptionThrown = false;
    try {
      new BuyerGroupAvailabilityExportBatch(createConfig(store.Id)).start(null);
    } catch (CatalogJobConfigException ex) {
      exceptionThrown = true;
      System.assert(ex.getMessage().contains('No BuyerGroup records found'));
    }

    System.assertEquals(
      true,
      exceptionThrown,
      'A store without Buyer Groups should fail fast'
    );
  }

  @IsTest
  static void testVisiblePolicyAndExportedItemHelpers_filterToVisibleScopedProducts() {
    Product2 hardwareProduct = createProduct('SKU-HARD-001', 'Hardware');
    Product2 plumbingProduct = createProduct('SKU-PIPE-001', 'Plumbing');
    Product2 outsideCatalogProduct = createProduct('SKU-OUT-001', 'Hardware');
    ProductCatalog catalog = createCatalogWithProducts(
      new List<Product2>{ hardwareProduct, plumbingProduct }
    );

    WebStore store = createWebStore('Availability Helper Store');
    SObject buyerGroup = createBuyerGroup('Helper Buyers');
    linkWebStoreBuyerGroup(store.Id, (Id) buyerGroup.get('Id'));

    SObject visiblePolicy = createPolicy('Visible Policy', true, false);
    SObject hiddenPolicy = createPolicy('Hidden Policy', false, false);
    linkPolicyBuyerGroup((Id) visiblePolicy.get('Id'), (Id) buyerGroup.get('Id'));
    linkPolicyBuyerGroup((Id) hiddenPolicy.get('Id'), (Id) buyerGroup.get('Id'));
    linkPolicyProduct((Id) visiblePolicy.get('Id'), hardwareProduct.Id);
    linkPolicyProduct((Id) visiblePolicy.get('Id'), plumbingProduct.Id);
    linkPolicyProduct((Id) visiblePolicy.get('Id'), outsideCatalogProduct.Id);
    linkPolicyProduct((Id) hiddenPolicy.get('Id'), hardwareProduct.Id);

    CatalogJobConfig__mdt config = createConfig(store.Id);
    config.CatalogId__c = String.valueOf(catalog.Id);

    BuyerGroupAvailabilityExportBatch batch =
      new BuyerGroupAvailabilityExportBatch(config);

    Map<Id, Set<Id>> visiblePolicyIdsByBuyerGroup =
      batch.getVisiblePolicyIdsByBuyerGroup(
        new Set<Id>{ (Id) buyerGroup.get('Id') }
      );

    System.assertEquals(
      new Set<Id>{ (Id) visiblePolicy.get('Id') },
      visiblePolicyIdsByBuyerGroup.get((Id) buyerGroup.get('Id')),
      'Only CanViewProduct policies should be returned'
    );

    Map<Id, Set<String>> exportedItemIdsByBuyerGroup =
      batch.getExportedItemIdsByBuyerGroup(visiblePolicyIdsByBuyerGroup);

    System.assertEquals(
      new Set<String>{ 'SKU-HARD-001' },
      exportedItemIdsByBuyerGroup.get((Id) buyerGroup.get('Id')),
      'Catalog and filter scoping should remove non-matching or out-of-catalog products'
    );
    System.assertEquals(
      0,
      batch.getVisiblePolicyIdsByBuyerGroup(new Set<Id>()).size(),
      'Empty Buyer Group inputs should return no policies'
    );
    System.assertEquals(
      0,
      batch.getExportedItemIdsByBuyerGroup(new Map<Id, Set<Id>>()).size(),
      'Empty policy maps should return no item ids'
    );
  }

  @IsTest
  static void testExecute_uploadsAvailabilityPayloadAndLogsPayload() {
    recordedRequests.clear();

    Product2 hardwareProduct = createProduct('SKU-HARD-100', 'Hardware');
    Product2 plumbingProduct = createProduct('SKU-PIPE-200', 'Plumbing');
    ProductCatalog catalog = createCatalogWithProducts(
      new List<Product2>{ hardwareProduct, plumbingProduct }
    );

    WebStore store = createWebStore('Availability Execute Store');
    SObject allBuyerGroup = createBuyerGroup('All Buyers');
    SObject filteredBuyerGroup = createBuyerGroup('Filtered Buyers');
    linkWebStoreBuyerGroup(store.Id, (Id) allBuyerGroup.get('Id'));
    linkWebStoreBuyerGroup(store.Id, (Id) filteredBuyerGroup.get('Id'));

    SObject allPolicy = createPolicy('All Buyers Policy', true, true);
    SObject filteredPolicy = createPolicy('Filtered Buyers Policy', true, false);
    linkPolicyBuyerGroup((Id) allPolicy.get('Id'), (Id) allBuyerGroup.get('Id'));
    linkPolicyBuyerGroup(
      (Id) filteredPolicy.get('Id'),
      (Id) filteredBuyerGroup.get('Id')
    );
    linkPolicyProduct((Id) allPolicy.get('Id'), hardwareProduct.Id);
    linkPolicyProduct((Id) allPolicy.get('Id'), plumbingProduct.Id);
    linkPolicyProduct((Id) filteredPolicy.get('Id'), plumbingProduct.Id);

    CatalogJobConfig__mdt config = createConfig(store.Id);
    config.CatalogId__c = String.valueOf(catalog.Id);

    BuyerGroupAvailabilityExportBatch batch =
      new BuyerGroupAvailabilityExportBatch(config);

    List<SObject> scope = queryBuyerGroups(
      new Set<Id>{
        (Id) allBuyerGroup.get('Id'),
        (Id) filteredBuyerGroup.get('Id')
      }
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
            '{"deletedCount":2}'
          )
        }
      )
    );

    Test.startTest();
    batch.execute(null, scope);
    Test.stopTest();

    System.assertEquals(42L, batch.firstOrderingId);
    System.assertEquals(
      3,
      recordedRequests.size(),
      'create container, upload, and stream update should all run'
    );
    System.assert(recordedRequests[0].getEndpoint().contains('/files'));
    System.assertEquals('abc', recordedRequests[1].getHeader('x-amz-meta-test'));
    System.assert(recordedRequests[2].getEndpoint().contains('/stream/update'));

    List<Coveo_Payload_Log__c> logs = [
      SELECT ScopeSize__c, OperationCount__c, IsValid__c, Reason__c, Payload__c
      FROM Coveo_Payload_Log__c
    ];
    System.assertEquals(1, logs.size(), 'Payload logging should enqueue one log');
    System.assertEquals(2, logs[0].ScopeSize__c.intValue());
    System.assertEquals(true, logs[0].IsValid__c);
    System.assert(logs[0].Payload__c.contains('"objecttype":"Availability"'));
    System.assert(logs[0].Payload__c.contains('SKU-HARD-100'));
    System.assert(
      !logs[0].Payload__c.contains('SKU-PIPE-200'),
      'Filtered products should not be exported in the availability payload'
    );
  }

  @IsTest
  static void testFinish_deletesOlderItemsWhenOrderingIdPresent() {
    recordedRequests.clear();

    WebStore store = createWebStore('Availability Finish Store');
    CatalogJobConfig__mdt config = createConfig(store.Id);
    config.EnablePayloadLogging__c = false;

    BuyerGroupAvailabilityExportBatch batch =
      new BuyerGroupAvailabilityExportBatch(config);
    batch.firstOrderingId = 84L;

    Test.setMock(
      HttpCalloutMock.class,
      new RecordingHttpMock(
        new Map<String, MockResponse>{
          '/deleteolderthan/' => new MockResponse(
            200,
            '200 OK',
            '{"deletedCount":1}'
          )
        }
      )
    );

    Test.startTest();
    batch.finish(null);
    Test.stopTest();

    System.assertEquals(1, recordedRequests.size());
    System.assert(recordedRequests[0].getEndpoint().contains('/deleteolderthan/'));
  }

  private static void assertConfigFailure(
    CatalogJobConfig__mdt config,
    String messageFragment
  ) {
    Boolean exceptionThrown = false;
    try {
      new BuyerGroupAvailabilityExportBatch(config);
    } catch (CatalogJobConfigException ex) {
      exceptionThrown = true;
      System.assert(ex.getMessage().contains(messageFragment));
    }

    System.assertEquals(
      true,
      exceptionThrown,
      'The batch constructor should reject invalid availability configs'
    );
  }
}
