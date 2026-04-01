@IsTest
private class CatalogBuyerGroupEntitlementProviderTest {
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
    Schema.SObjectType webStoreType = Schema.getGlobalDescribe().get('WebStore');
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

  private static Product2 createProduct(String code) {
    Product2 product = new Product2(
      Name = 'Entitlement Provider ' + code,
      ProductCode = code,
      Family = 'Hardware',
      IsActive = true
    );
    insert product;
    return product;
  }

  @IsTest
  static void testGetRequiredProductFieldsForBuyerGroupAccess_returnsEmptyList() {
    System.assertEquals(
      0,
      new CatalogBuyerGroupEntitlementProvider()
        .getRequiredProductFieldsForBuyerGroupAccess()
        .size()
    );
  }

  @IsTest
  static void testResolveBuyerGroupAccess_handlesIncompleteInputsGracefully() {
    CatalogBuyerGroupEntitlementProvider provider =
      new CatalogBuyerGroupEntitlementProvider();

    System.assertEquals(
      0,
      provider.resolveBuyerGroupAccess(
        null,
        new List<Product2>(),
        new Map<Id, String>()
      ).size()
    );
    System.assertEquals(
      0,
      provider.resolveBuyerGroupAccess(
        new CatalogJobConfig__mdt(WebStoreId__c = '0ZE000000000001AAA'),
        new List<Product2>(),
        new Map<Id, String>()
      ).size()
    );

    Product2 product = new Product2(
      Id = Id.valueOf('01t000000000501AAA'),
      ProductCode = 'SKU-501'
    );
    System.assertEquals(
      0,
      provider.resolveBuyerGroupAccess(
        new CatalogJobConfig__mdt(WebStoreId__c = '0ZE000000000001AAA'),
        new List<Product2>{ product },
        new Map<Id, String>()
      ).size(),
      'Products without resolved ec_product_id values should be ignored'
    );
  }

  @IsTest
  static void testResolveBuyerGroupAccess_returnsEmptyWhenStoreHasNoBuyerGroupsOrPolicies() {
    if (!hasCommerceAvailabilitySchema()) {
      return;
    }

    CatalogBuyerGroupEntitlementProvider provider =
      new CatalogBuyerGroupEntitlementProvider();

    SObject emptyStore = createWebStore('Provider Empty Store');
    Product2 product = createProduct('SKU-EMPTY-001');
    Map<Id, String> ecProductIdByProductId = new Map<Id, String>{
      product.Id => 'EC-EMPTY-001'
    };

    System.assertEquals(
      0,
      provider.resolveBuyerGroupAccess(
        new CatalogJobConfig__mdt(
          WebStoreId__c = String.valueOf(emptyStore.get('Id'))
        ),
        new List<Product2>{ product },
        ecProductIdByProductId
      ).size(),
      'Stores without Buyer Groups should not yield snapshots'
    );

    SObject noPolicyStore = createWebStore('Provider No Policy Store');
    SObject buyerGroup = createBuyerGroup('Provider No Policy Buyers');
    linkWebStoreBuyerGroup(
      (Id) noPolicyStore.get('Id'),
      (Id) buyerGroup.get('Id')
    );

    System.assertEquals(
      0,
      provider.resolveBuyerGroupAccess(
        new CatalogJobConfig__mdt(
          WebStoreId__c = String.valueOf(noPolicyStore.get('Id'))
        ),
        new List<Product2>{ product },
        ecProductIdByProductId
      ).size(),
      'Buyer Groups without visible entitlement policies should not yield snapshots'
    );
  }

  @IsTest
  static void testResolveBuyerGroupAccess_returnsVisibleEntitlementsByProduct() {
    if (!hasCommerceAvailabilitySchema()) {
      return;
    }

    CatalogBuyerGroupEntitlementProvider provider =
      new CatalogBuyerGroupEntitlementProvider();

    Product2 alphaProduct = createProduct('SKU-ALPHA-001');
    Product2 betaProduct = createProduct('SKU-BETA-001');
    Product2 ignoredProduct = createProduct('SKU-IGNORED-001');

    SObject store = createWebStore('Provider Coverage Store');
    SObject alphaBuyerGroup = createBuyerGroup('Alpha Buyers');
    SObject betaBuyerGroup = createBuyerGroup('Beta Buyers');
    linkWebStoreBuyerGroup((Id) store.get('Id'), (Id) alphaBuyerGroup.get('Id'));
    linkWebStoreBuyerGroup((Id) store.get('Id'), (Id) betaBuyerGroup.get('Id'));

    SObject alphaVisiblePolicy = createPolicy('Alpha Visible Policy', true, false);
    SObject alphaHiddenPolicy = createPolicy('Alpha Hidden Policy', false, false);
    SObject betaVisiblePolicy = createPolicy('Beta Visible Policy', true, true);
    linkPolicyBuyerGroup(
      (Id) alphaVisiblePolicy.get('Id'),
      (Id) alphaBuyerGroup.get('Id')
    );
    linkPolicyBuyerGroup(
      (Id) alphaHiddenPolicy.get('Id'),
      (Id) alphaBuyerGroup.get('Id')
    );
    linkPolicyBuyerGroup(
      (Id) betaVisiblePolicy.get('Id'),
      (Id) betaBuyerGroup.get('Id')
    );

    linkPolicyProduct((Id) alphaVisiblePolicy.get('Id'), alphaProduct.Id);
    linkPolicyProduct((Id) alphaHiddenPolicy.get('Id'), betaProduct.Id);
    linkPolicyProduct((Id) betaVisiblePolicy.get('Id'), betaProduct.Id);
    linkPolicyProduct((Id) alphaVisiblePolicy.get('Id'), ignoredProduct.Id);

    Map<Id, CatalogBuyerGroupAccessSnapshot> snapshotsByProductId =
      provider.resolveBuyerGroupAccess(
        new CatalogJobConfig__mdt(
          WebStoreId__c = String.valueOf(store.get('Id'))
        ),
        new List<Product2>{ alphaProduct, betaProduct, ignoredProduct },
        new Map<Id, String>{
          alphaProduct.Id => 'EC-ALPHA-001',
          betaProduct.Id => 'EC-BETA-001'
        }
      );

    System.assertEquals(
      2,
      snapshotsByProductId.size(),
      'Only products with resolved ec_product_id values and visible entitlements should be returned'
    );

    CatalogBuyerGroupAccessSnapshot alphaSnapshot = snapshotsByProductId.get(
      alphaProduct.Id
    );
    System.assertEquals('EC-ALPHA-001', alphaSnapshot.ecProductId);
    System.assertEquals(
      JSON.serialize(new List<String>{ String.valueOf(alphaBuyerGroup.get('Id')) }),
      JSON.serialize(alphaSnapshot.getSortedBuyerGroupIds())
    );
    System.assertEquals(
      JSON.serialize(new List<String>{ 'Alpha Buyers' }),
      JSON.serialize(alphaSnapshot.getSortedBuyerGroupNames())
    );

    CatalogBuyerGroupAccessSnapshot betaSnapshot = snapshotsByProductId.get(
      betaProduct.Id
    );
    System.assertEquals('EC-BETA-001', betaSnapshot.ecProductId);
    System.assertEquals(
      JSON.serialize(new List<String>{ String.valueOf(betaBuyerGroup.get('Id')) }),
      JSON.serialize(betaSnapshot.getSortedBuyerGroupIds()),
      'Hidden policies should not contribute Buyer Group memberships'
    );
    System.assertEquals(
      JSON.serialize(new List<String>{ 'Beta Buyers' }),
      JSON.serialize(betaSnapshot.getSortedBuyerGroupNames())
    );
    System.assertEquals(
      String.valueOf(store.get('Id')),
      betaSnapshot.webStoreId
    );
    System.assertEquals(
      false,
      snapshotsByProductId.containsKey(ignoredProduct.Id),
      'Products without resolved ec_product_id values should be skipped even when policies exist'
    );
  }
}
