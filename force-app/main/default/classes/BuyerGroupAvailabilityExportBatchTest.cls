@IsTest
private class BuyerGroupAvailabilityExportBatchTest {
  private static List<HttpRequest> recordedRequests = new List<HttpRequest>();
  private static final Id FALLBACK_WEB_STORE_ID = Id.valueOf(
    '001000000000001AAA'
  );

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
    return createConfig(webStoreId, null);
  }

  private static CatalogJobConfig__mdt createConfig(
    Id webStoreId,
    String builderType
  ) {
    return new CatalogJobConfig__mdt(
      DeveloperName = 'BuyerGroupAvailabilityTest',
      MasterLabel = 'Buyer Group Availability Test',
      CoveoOrgId__c = 'org-availability-test',
      AvailabilitySourceId__c = 'availability-source-test',
      WebStoreId__c = String.valueOf(webStoreId),
      EnableBuyerGroupAvailability__c = true,
      BuyerGroupAvailabilityMode__c = CatalogBuyerGroupAvailabilityMode.PAIRED_SOURCE,
      EnablePayloadLogging__c = true,
      ProductFilter__c = 'Family = \'Hardware\'',
      BuilderType__c = builderType,
      BatchSize__c = 10
    );
  }

  private static Boolean hasCommerceAvailabilitySchema() {
    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    return globalDescribe.containsKey('WebStore') &&
      globalDescribe.containsKey('BuyerGroup') &&
      globalDescribe.containsKey('WebStoreBuyerGroup') &&
      globalDescribe.containsKey('CommerceEntitlementPolicy') &&
      globalDescribe.containsKey('CommerceEntitlementBuyerGroup') &&
      globalDescribe.containsKey('CommerceEntitlementProduct');
  }

  private static SObject createWebStore(String name) {
    Schema.SObjectType webStoreType = Schema.getGlobalDescribe()
      .get('WebStore');
    System.assertNotEquals(
      null,
      webStoreType,
      'WebStore should only be created in orgs where Commerce availability schema exists.'
    );

    SObject store = webStoreType.newSObject();
    store.put('Name', name);
    store.put('OptionsAutoFacetingEnabled', false);
    store.put('OptionsCartAsyncProcessingEnabled', false);
    store.put('OptionsCartCalculateEnabled', false);
    store.put('OptionsCartToOrderAutoCustomFieldMapping', false);
    store.put('OptionsCommerceEinsteinActivitiesTracked', false);
    store.put('OptionsCommerceEinsteinDeployed', false);
    store.put('OptionsDuplicateCartItemsEnabled', false);
    store.put('OptionsGuestBrowsingEnabled', false);
    store.put('OptionsGuestCartEnabled', false);
    store.put('OptionsGuestCheckoutEnabled', false);
    store.put('OptionsPreserveGuestCartEnabled', false);
    store.put('OptionsSkipAdditionalEntitlementCheckForSearch', false);
    store.put('OptionsSkuDetectionEnabled', false);
    store.put('OptionsSplitShipmentEnabled', false);
    insert store;
    return store;
  }

  private static SObject createBuyerGroup(String name) {
    SObject buyerGroup = Schema.getGlobalDescribe()
      .get('BuyerGroup')
      .newSObject();
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
    SObject link = Schema.getGlobalDescribe()
      .get('WebStoreBuyerGroup')
      .newSObject();
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
    return createProduct(code, family, null);
  }

  private static Product2 createProduct(
    String code,
    String family,
    String stockKeepingUnit
  ) {
    Product2 product = new Product2(
      Name = 'Availability Test ' + code,
      ProductCode = code,
      StockKeepingUnit = stockKeepingUnit,
      Family = family,
      IsActive = true
    );
    insert product;
    return product;
  }

  private static ProductCatalog createCatalogWithProducts(
    List<Product2> products
  ) {
    ProductCatalog catalog = new ProductCatalog(
      Name = 'Availability Test Catalog'
    );
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

  private static List<String> readQueryLocatorNames(
    Database.QueryLocator locator
  ) {
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
    CatalogJobConfig__mdt disabledConfig = createConfig(FALLBACK_WEB_STORE_ID);
    disabledConfig.EnableBuyerGroupAvailability__c = false;
    disabledConfig.BuyerGroupAvailabilityMode__c = CatalogBuyerGroupAvailabilityMode.DISABLED;
    assertConfigFailure(disabledConfig, 'PairedSource or DualWrite');

    CatalogJobConfig__mdt missingSourceConfig = createConfig(
      FALLBACK_WEB_STORE_ID
    );
    missingSourceConfig.AvailabilitySourceId__c = null;
    assertConfigFailure(
      missingSourceConfig,
      'AvailabilitySourceId__c is required'
    );

    CatalogJobConfig__mdt missingStoreConfig = createConfig(
      FALLBACK_WEB_STORE_ID
    );
    missingStoreConfig.WebStoreId__c = null;
    assertConfigFailure(missingStoreConfig, 'WebStoreId__c is required');
  }

  @IsTest
  static void testStart_returnsBuyerGroupsForConfiguredStore() {
    if (!hasCommerceAvailabilitySchema()) {
      return;
    }

    SObject store = createWebStore('Availability Start Store');
    Id storeId = (Id) store.get('Id');
    SObject alphaBuyerGroup = createBuyerGroup('Alpha Buyers');
    SObject betaBuyerGroup = createBuyerGroup('Beta Buyers');
    linkWebStoreBuyerGroup(storeId, (Id) alphaBuyerGroup.get('Id'));
    linkWebStoreBuyerGroup(storeId, (Id) betaBuyerGroup.get('Id'));

    BuyerGroupAvailabilityExportBatch batch = new BuyerGroupAvailabilityExportBatch(
      createConfig(storeId)
    );

    List<String> names = readQueryLocatorNames(batch.start(null));

    System.assertEquals(
      new List<String>{ 'Alpha Buyers', 'Beta Buyers' },
      names,
      'The start query should scope Buyer Groups to the configured store'
    );
  }

  @IsTest
  static void testStart_unionsBuyerGroupsAcrossConfiguredStores() {
    if (!hasCommerceAvailabilitySchema()) {
      return;
    }

    Id firstStoreId = (Id) createWebStore('First Union Store').get('Id');
    Id secondStoreId = (Id) createWebStore('Second Union Store').get('Id');
    SObject firstOnlyGroup = createBuyerGroup('First Only Buyers');
    SObject sharedGroup = createBuyerGroup('Shared Buyers');
    SObject secondOnlyGroup = createBuyerGroup('Second Only Buyers');
    linkWebStoreBuyerGroup(firstStoreId, (Id) firstOnlyGroup.get('Id'));
    linkWebStoreBuyerGroup(firstStoreId, (Id) sharedGroup.get('Id'));
    linkWebStoreBuyerGroup(secondStoreId, (Id) sharedGroup.get('Id'));
    linkWebStoreBuyerGroup(secondStoreId, (Id) secondOnlyGroup.get('Id'));

    CatalogJobConfig__mdt config = createConfig(firstStoreId);
    config.WebStoreId__c = null;
    config.WebStoreIds__c = String.join(
      new List<String>{
        String.valueOf(firstStoreId),
        String.valueOf(secondStoreId)
      },
      ','
    );

    BuyerGroupAvailabilityExportBatch batch = new BuyerGroupAvailabilityExportBatch(
      config
    );
    System.assertEquals(
      new List<String>{
        'First Only Buyers',
        'Second Only Buyers',
        'Shared Buyers'
      },
      readQueryLocatorNames(batch.start(null)),
      'Multi-store availability should union and de-duplicate Buyer Groups'
    );

    Map<Id, Set<String>> storesByGroup = BuyerGroupAvailabilityExportBatch.getBuyerGroupIdsForWebStores(
      new Set<Id>{ firstStoreId, secondStoreId }
    );
    System.assertEquals(
      new Set<String>{
        String.valueOf(firstStoreId),
        String.valueOf(secondStoreId)
      },
      storesByGroup.get((Id) sharedGroup.get('Id')),
      'A shared Buyer Group should retain both contributing store IDs'
    );
  }

  @IsTest
  static void testMultiStorePayload_emitsSortedPluralStoreIds() {
    if (!hasCommerceAvailabilitySchema()) {
      return;
    }

    SObject buyerGroup = createBuyerGroup('Multi Store Payload Buyers');
    Id buyerGroupId = (Id) buyerGroup.get('Id');
    String payload = BuyerGroupAvailabilityPayloadBuilder.buildFullUpdateNdjson(
      new List<SObject>{ buyerGroup },
      new Map<Id, Set<String>>{
        buyerGroupId => new Set<String>{ 'SKU-002', 'SKU-001' }
      },
      new Map<Id, Set<String>>{
        buyerGroupId => new Set<String>{
          '0ZE000000000002AAA',
          '0ZE000000000001AAA'
        }
      }
    );
    Map<String, Object> envelope = (Map<String, Object>) JSON.deserializeUntyped(
      payload
    );
    Map<String, Object> item = (Map<String, Object>) ((List<Object>) envelope.get(
      'addOrUpdate'
    ))[0];

    System.assertEquals(
      new List<Object>{ 'SKU-001', 'SKU-002' },
      item.get('ec_available_items')
    );
    System.assertEquals(
      new List<Object>{ '0ZE000000000001AAA', '0ZE000000000002AAA' },
      item.get('sf_webstore_ids')
    );
    System.assertEquals(
      false,
      item.containsKey('sf_webstore_id'),
      'The singular field should only be emitted when exactly one store applies'
    );
  }

  @IsTest
  static void testStart_throwsWhenStoreHasNoBuyerGroups() {
    if (!hasCommerceAvailabilitySchema()) {
      return;
    }

    SObject store = createWebStore('Empty Availability Store');
    Id storeId = (Id) store.get('Id');

    Boolean exceptionThrown = false;
    try {
      new BuyerGroupAvailabilityExportBatch(createConfig(storeId)).start(null);
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
    if (!hasCommerceAvailabilitySchema()) {
      BuyerGroupAvailabilityExportBatch batch = new BuyerGroupAvailabilityExportBatch(
        createConfig(FALLBACK_WEB_STORE_ID)
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
      return;
    }

    Product2 hardwareProduct = createProduct('SKU-HARD-001', 'Hardware');
    Product2 plumbingProduct = createProduct('SKU-PIPE-001', 'Plumbing');
    Product2 outsideCatalogProduct = createProduct('SKU-OUT-001', 'Hardware');
    ProductCatalog catalog = createCatalogWithProducts(
      new List<Product2>{ hardwareProduct, plumbingProduct }
    );

    SObject store = createWebStore('Availability Helper Store');
    Id storeId = (Id) store.get('Id');
    SObject buyerGroup = createBuyerGroup('Helper Buyers');
    linkWebStoreBuyerGroup(storeId, (Id) buyerGroup.get('Id'));

    SObject visiblePolicy = createPolicy('Visible Policy', true, false);
    SObject hiddenPolicy = createPolicy('Hidden Policy', false, false);
    linkPolicyBuyerGroup(
      (Id) visiblePolicy.get('Id'),
      (Id) buyerGroup.get('Id')
    );
    linkPolicyBuyerGroup(
      (Id) hiddenPolicy.get('Id'),
      (Id) buyerGroup.get('Id')
    );
    linkPolicyProduct((Id) visiblePolicy.get('Id'), hardwareProduct.Id);
    linkPolicyProduct((Id) visiblePolicy.get('Id'), plumbingProduct.Id);
    linkPolicyProduct((Id) visiblePolicy.get('Id'), outsideCatalogProduct.Id);
    linkPolicyProduct((Id) hiddenPolicy.get('Id'), hardwareProduct.Id);

    CatalogJobConfig__mdt config = createConfig(storeId);
    config.CatalogId__c = String.valueOf(catalog.Id);

    BuyerGroupAvailabilityExportBatch batch = new BuyerGroupAvailabilityExportBatch(
      config
    );

    Map<Id, Set<Id>> visiblePolicyIdsByBuyerGroup = batch.getVisiblePolicyIdsByBuyerGroup(
      new Set<Id>{ (Id) buyerGroup.get('Id') }
    );

    System.assertEquals(
      new Set<Id>{ (Id) visiblePolicy.get('Id') },
      visiblePolicyIdsByBuyerGroup.get((Id) buyerGroup.get('Id')),
      'Only CanViewProduct policies should be returned'
    );

    Map<Id, Set<String>> exportedItemIdsByBuyerGroup = batch.getExportedItemIdsByBuyerGroup(
      visiblePolicyIdsByBuyerGroup
    );

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
  static void testGetExportedItemIdsByBuyerGroup_customIdentityProviderUsesStockKeepingUnit() {
    if (!hasCommerceAvailabilitySchema()) {
      return;
    }

    Product2 hardwareProduct = createProduct(
      'SKU-HARD-ALT-001',
      'Hardware',
      'STOCK-HARD-ALT-001'
    );
    ProductCatalog catalog = createCatalogWithProducts(
      new List<Product2>{ hardwareProduct }
    );

    SObject store = createWebStore('Availability Provider Store');
    Id storeId = (Id) store.get('Id');
    SObject buyerGroup = createBuyerGroup('Provider Buyers');
    linkWebStoreBuyerGroup(storeId, (Id) buyerGroup.get('Id'));

    SObject visiblePolicy = createPolicy('Provider Policy', true, false);
    linkPolicyBuyerGroup(
      (Id) visiblePolicy.get('Id'),
      (Id) buyerGroup.get('Id')
    );
    linkPolicyProduct((Id) visiblePolicy.get('Id'), hardwareProduct.Id);

    CatalogJobConfig__mdt config = createConfig(
      storeId,
      'CatalogJsonBuilderSkuIdentityStub'
    );
    config.CatalogId__c = String.valueOf(catalog.Id);

    BuyerGroupAvailabilityExportBatch batch = new BuyerGroupAvailabilityExportBatch(
      config
    );

    Map<Id, Set<String>> exportedItemIdsByBuyerGroup = batch.getExportedItemIdsByBuyerGroup(
      batch.getVisiblePolicyIdsByBuyerGroup(
        new Set<Id>{ (Id) buyerGroup.get('Id') }
      )
    );

    System.assertEquals(
      new Set<String>{ 'STOCK-HARD-ALT-001' },
      exportedItemIdsByBuyerGroup.get((Id) buyerGroup.get('Id')),
      'Availability should align with the custom builder identity provider output'
    );
  }

  @IsTest
  static void testGetExportedItemIdsByBuyerGroup_legacyBuilderFallsBackToProductCode() {
    if (!hasCommerceAvailabilitySchema()) {
      return;
    }

    Product2 hardwareProduct = createProduct(
      'SKU-HARD-LEGACY-001',
      'Hardware',
      'STOCK-HARD-LEGACY-001'
    );
    ProductCatalog catalog = createCatalogWithProducts(
      new List<Product2>{ hardwareProduct }
    );

    SObject store = createWebStore('Availability Legacy Store');
    Id storeId = (Id) store.get('Id');
    SObject buyerGroup = createBuyerGroup('Legacy Buyers');
    linkWebStoreBuyerGroup(storeId, (Id) buyerGroup.get('Id'));

    SObject visiblePolicy = createPolicy('Legacy Policy', true, false);
    linkPolicyBuyerGroup(
      (Id) visiblePolicy.get('Id'),
      (Id) buyerGroup.get('Id')
    );
    linkPolicyProduct((Id) visiblePolicy.get('Id'), hardwareProduct.Id);

    CatalogJobConfig__mdt config = createConfig(
      storeId,
      'CatalogJsonBuilderLegacyTestStub'
    );
    config.CatalogId__c = String.valueOf(catalog.Id);

    BuyerGroupAvailabilityExportBatch batch = new BuyerGroupAvailabilityExportBatch(
      config
    );

    Map<Id, Set<String>> exportedItemIdsByBuyerGroup = batch.getExportedItemIdsByBuyerGroup(
      batch.getVisiblePolicyIdsByBuyerGroup(
        new Set<Id>{ (Id) buyerGroup.get('Id') }
      )
    );

    System.assertEquals(
      new Set<String>{ 'SKU-HARD-LEGACY-001' },
      exportedItemIdsByBuyerGroup.get((Id) buyerGroup.get('Id')),
      'Legacy builders should continue to fall back to ProductCode, then Id'
    );
  }

  @IsTest
  static void testGetExportedItemIdsByBuyerGroup_rejectsBlankIdentityProviderValues() {
    if (!hasCommerceAvailabilitySchema()) {
      return;
    }

    Product2 hardwareProduct = createProduct('SKU-HARD-BROKEN-001', 'Hardware');
    ProductCatalog catalog = createCatalogWithProducts(
      new List<Product2>{ hardwareProduct }
    );

    SObject store = createWebStore('Availability Broken Store');
    Id storeId = (Id) store.get('Id');
    SObject buyerGroup = createBuyerGroup('Broken Buyers');
    linkWebStoreBuyerGroup(storeId, (Id) buyerGroup.get('Id'));

    SObject visiblePolicy = createPolicy('Broken Policy', true, false);
    linkPolicyBuyerGroup(
      (Id) visiblePolicy.get('Id'),
      (Id) buyerGroup.get('Id')
    );
    linkPolicyProduct((Id) visiblePolicy.get('Id'), hardwareProduct.Id);

    CatalogJobConfig__mdt config = createConfig(
      storeId,
      'CatalogJsonBuilderBrokenIdentityTestStub'
    );
    config.CatalogId__c = String.valueOf(catalog.Id);

    BuyerGroupAvailabilityExportBatch batch = new BuyerGroupAvailabilityExportBatch(
      config
    );

    Boolean failed = false;
    try {
      batch.getExportedItemIdsByBuyerGroup(
        batch.getVisiblePolicyIdsByBuyerGroup(
          new Set<Id>{ (Id) buyerGroup.get('Id') }
        )
      );
    } catch (CatalogJobException ex) {
      failed = true;
      System.assert(ex.getMessage().contains('blank ec_product_id'));
    }

    System.assertEquals(true, failed);
  }

  @IsTest
  static void testExecute_uploadsAvailabilityPayloadAndLogsPayload() {
    recordedRequests.clear();

    if (!hasCommerceAvailabilitySchema()) {
      CatalogJobConfig__mdt config = createConfig(FALLBACK_WEB_STORE_ID);
      BuyerGroupAvailabilityExportBatch batch = new BuyerGroupAvailabilityExportBatch(
        config
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
            )
          }
        )
      );

      Test.startTest();
      batch.execute(null, new List<SObject>());
      Test.stopTest();

      System.assertEquals(42L, batch.firstOrderingId);
      System.assertEquals(
        3,
        recordedRequests.size(),
        'Empty-scope execution should still upload and stream an empty payload'
      );

      List<Coveo_Payload_Log__c> logs = [
        SELECT
          ScopeSize__c,
          OperationCount__c,
          IsValid__c,
          Reason__c,
          Payload__c
        FROM Coveo_Payload_Log__c
      ];
      System.assertEquals(1, logs.size(), 'Payload logging should still occur');
      System.assertEquals(0, logs[0].ScopeSize__c.intValue());
      System.assertEquals(
        false,
        logs[0].IsValid__c,
        'An empty payload should be logged as invalid because it has no operations'
      );
      System.assert(
        logs[0].Reason__c.contains('No operations found'),
        'The validator should explain why the empty payload is invalid'
      );
      System.assertEquals(
        '{"addOrUpdate":[]}',
        logs[0].Payload__c,
        'Empty-scope execution should export an empty availability payload'
      );
      return;
    }

    Product2 hardwareProduct = createProduct('SKU-HARD-100', 'Hardware');
    Product2 plumbingProduct = createProduct('SKU-PIPE-200', 'Plumbing');
    ProductCatalog catalog = createCatalogWithProducts(
      new List<Product2>{ hardwareProduct, plumbingProduct }
    );

    SObject store = createWebStore('Availability Execute Store');
    Id storeId = (Id) store.get('Id');
    SObject allBuyerGroup = createBuyerGroup('All Buyers');
    SObject filteredBuyerGroup = createBuyerGroup('Filtered Buyers');
    linkWebStoreBuyerGroup(storeId, (Id) allBuyerGroup.get('Id'));
    linkWebStoreBuyerGroup(storeId, (Id) filteredBuyerGroup.get('Id'));

    SObject allPolicy = createPolicy('All Buyers Policy', true, true);
    SObject filteredPolicy = createPolicy(
      'Filtered Buyers Policy',
      true,
      false
    );
    linkPolicyBuyerGroup(
      (Id) allPolicy.get('Id'),
      (Id) allBuyerGroup.get('Id')
    );
    linkPolicyBuyerGroup(
      (Id) filteredPolicy.get('Id'),
      (Id) filteredBuyerGroup.get('Id')
    );
    linkPolicyProduct((Id) allPolicy.get('Id'), hardwareProduct.Id);
    linkPolicyProduct((Id) allPolicy.get('Id'), plumbingProduct.Id);
    linkPolicyProduct((Id) filteredPolicy.get('Id'), plumbingProduct.Id);

    CatalogJobConfig__mdt config = createConfig(storeId);
    config.CatalogId__c = String.valueOf(catalog.Id);

    BuyerGroupAvailabilityExportBatch batch = new BuyerGroupAvailabilityExportBatch(
      config
    );

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
    System.assertEquals(
      'abc',
      recordedRequests[1].getHeader('x-amz-meta-test')
    );
    System.assert(recordedRequests[2].getEndpoint().contains('/stream/update'));

    List<Coveo_Payload_Log__c> logs = [
      SELECT ScopeSize__c, OperationCount__c, IsValid__c, Reason__c, Payload__c
      FROM Coveo_Payload_Log__c
    ];
    System.assertEquals(
      1,
      logs.size(),
      'Payload logging should enqueue one log'
    );
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

    CatalogJobConfig__mdt config = createConfig(FALLBACK_WEB_STORE_ID);
    config.EnablePayloadLogging__c = false;

    BuyerGroupAvailabilityExportBatch batch = new BuyerGroupAvailabilityExportBatch(
      config
    );
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
    System.assert(
      recordedRequests[0].getEndpoint().contains('/deleteolderthan/')
    );
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
