@IsTest
private class CatalogBuyerGroupAccessResolverTest {
  private class NullFieldAccessBuilder implements ICatalogJsonBuilder, ICatalogProductIdentityProvider, ICatalogBuyerGroupAccessProvider {
    public List<String> getRequiredProductFieldsForIdentity() {
      return new List<String>{ 'ProductCode' };
    }

    public Map<Id, String> resolveEcProductIds(List<Product2> products) {
      Map<Id, String> ecProductIds = new Map<Id, String>();
      for (Product2 product : products) {
        if (product != null && product.Id != null) {
          ecProductIds.put(product.Id, product.ProductCode);
        }
      }
      return ecProductIds;
    }

    public List<String> getRequiredProductFieldsForBuyerGroupAccess() {
      return null;
    }

    public Map<Id, CatalogBuyerGroupAccessSnapshot> resolveBuyerGroupAccess(
      CatalogJobConfig__mdt jobConfig,
      List<Product2> products,
      Map<Id, String> ecProductIdByProductId
    ) {
      Map<Id, CatalogBuyerGroupAccessSnapshot> snapshots = new Map<Id, CatalogBuyerGroupAccessSnapshot>();

      if (!products.isEmpty()) {
        CatalogBuyerGroupAccessSnapshot snapshot = new CatalogBuyerGroupAccessSnapshot();
        snapshot.productId = products[0].Id;
        snapshot.ecProductId = ecProductIdByProductId.get(products[0].Id);
        snapshot.webStoreId = null;
        snapshot.buyerGroupIds = null;
        snapshot.buyerGroupNames = null;
        snapshots.put(products[0].Id, snapshot);
      }

      return snapshots;
    }

    public String buildFullUpdateNdjson(
      List<Product2> products,
      Map<Id, Map<String, Decimal>> pricesByProduct,
      List<String> extraFieldNames
    ) {
      return JSON.serialize(
        new Map<String, Object>{ 'addOrUpdate' => new List<Object>() }
      );
    }

    public String buildPartialMergeNdjson(
      Map<String, Decimal> priceBySku,
      Map<String, Boolean> inStockBySku
    ) {
      return JSON.serialize(
        new Map<String, Object>{ 'addOrMerge' => new List<Object>() }
      );
    }
  }

  private class CustomAccessBuilder implements ICatalogJsonBuilder, ICatalogProductIdentityProvider, ICatalogBuyerGroupAccessProvider {
    public List<String> getRequiredProductFieldsForIdentity() {
      return new List<String>{ 'StockKeepingUnit' };
    }

    public Map<Id, String> resolveEcProductIds(List<Product2> products) {
      Map<Id, String> ecProductIds = new Map<Id, String>();
      for (Product2 product : products) {
        ecProductIds.put(product.Id, product.StockKeepingUnit);
      }
      return ecProductIds;
    }

    public List<String> getRequiredProductFieldsForBuyerGroupAccess() {
      return new List<String>{ 'ProductCode', 'Family', 'ProductCode' };
    }

    public Map<Id, CatalogBuyerGroupAccessSnapshot> resolveBuyerGroupAccess(
      CatalogJobConfig__mdt jobConfig,
      List<Product2> products,
      Map<Id, String> ecProductIdByProductId
    ) {
      Map<Id, CatalogBuyerGroupAccessSnapshot> snapshots = new Map<Id, CatalogBuyerGroupAccessSnapshot>();

      if (products.isEmpty()) {
        return snapshots;
      }

      Product2 firstProduct = products[0];
      CatalogBuyerGroupAccessSnapshot snapshot = new CatalogBuyerGroupAccessSnapshot();
      snapshot.productId = firstProduct.Id;
      snapshot.ecProductId = ecProductIdByProductId.get(firstProduct.Id);
      snapshot.webStoreId = 'custom-store';
      snapshot.buyerGroupIds.add('BG-2');
      snapshot.buyerGroupIds.add('BG-1');
      snapshot.buyerGroupNames.add('Beta');
      snapshot.buyerGroupNames.add('Alpha');
      snapshots.put(firstProduct.Id, snapshot);
      return snapshots;
    }

    public String buildFullUpdateNdjson(
      List<Product2> products,
      Map<Id, Map<String, Decimal>> pricesByProduct,
      List<String> extraFieldNames
    ) {
      return JSON.serialize(
        new Map<String, Object>{ 'addOrUpdate' => new List<Object>() }
      );
    }

    public String buildPartialMergeNdjson(
      Map<String, Decimal> priceBySku,
      Map<String, Boolean> inStockBySku
    ) {
      return JSON.serialize(
        new Map<String, Object>{ 'addOrMerge' => new List<Object>() }
      );
    }
  }

  @IsTest
  static void testGetRequiredProductFields_dedupesCustomProviderFields() {
    List<String> requiredFields = CatalogBuyerGroupAccessResolver.getRequiredProductFields(
      new CustomAccessBuilder()
    );

    System.assertEquals(
      new List<String>{ 'ProductCode', 'Family' },
      requiredFields
    );
  }

  @IsTest
  static void testResolveBuyerGroupAccess_normalizesMissingSnapshots() {
    String webStoreId = String.valueOf(Id.valueOf('0ZE000000000001'));
    List<Product2> products = new List<Product2>{
      new Product2(
        Id = Id.valueOf('01t000000000201AAA'),
        StockKeepingUnit = 'EC-201',
        ProductCode = 'SKU-201'
      ),
      new Product2(
        Id = Id.valueOf('01t000000000202AAA'),
        StockKeepingUnit = 'EC-202',
        ProductCode = 'SKU-202'
      )
    };
    CatalogJobConfig__mdt config = new CatalogJobConfig__mdt(
      WebStoreId__c = webStoreId
    );

    Map<Id, CatalogBuyerGroupAccessSnapshot> snapshots = CatalogBuyerGroupAccessResolver.resolveBuyerGroupAccess(
      config,
      products,
      new CustomAccessBuilder()
    );

    System.assertEquals(2, snapshots.size());
    System.assertEquals(
      JSON.serialize(new List<String>{ 'BG-1', 'BG-2' }),
      JSON.serialize(snapshots.get(products[0].Id).getSortedBuyerGroupIds())
    );
    System.assertEquals(
      JSON.serialize(new List<String>{ 'Alpha', 'Beta' }),
      JSON.serialize(snapshots.get(products[0].Id).getSortedBuyerGroupNames())
    );
    System.assertEquals(
      'EC-202',
      snapshots.get(products[1].Id).ecProductId,
      'Every in-scope product should receive a normalized snapshot entry'
    );
    System.assertEquals(
      0,
      snapshots.get(products[1].Id).buyerGroupIds.size(),
      'Products without provider output should normalize to empty memberships'
    );
    System.assertEquals(webStoreId, snapshots.get(products[1].Id).webStoreId);
  }

  @IsTest
  static void testIndexSnapshotsByEcProductId_mergesMemberships() {
    String webStoreId = String.valueOf(Id.valueOf('0ZE000000000002'));
    CatalogBuyerGroupAccessSnapshot firstSnapshot = new CatalogBuyerGroupAccessSnapshot();
    firstSnapshot.productId = Id.valueOf('01t000000000211AAA');
    firstSnapshot.ecProductId = 'EC-MERGED';
    firstSnapshot.webStoreId = webStoreId;
    firstSnapshot.buyerGroupIds.add('BG-2');
    firstSnapshot.buyerGroupNames.add('Beta');

    CatalogBuyerGroupAccessSnapshot secondSnapshot = new CatalogBuyerGroupAccessSnapshot();
    secondSnapshot.productId = Id.valueOf('01t000000000212AAA');
    secondSnapshot.ecProductId = 'EC-MERGED';
    secondSnapshot.webStoreId = webStoreId;
    secondSnapshot.buyerGroupIds.add('BG-1');
    secondSnapshot.buyerGroupNames.add('Alpha');

    Map<String, CatalogBuyerGroupAccessSnapshot> snapshotsByEcProductId = CatalogBuyerGroupAccessResolver.indexSnapshotsByEcProductId(
      new Map<Id, CatalogBuyerGroupAccessSnapshot>{
        firstSnapshot.productId => firstSnapshot,
        secondSnapshot.productId => secondSnapshot
      },
      webStoreId
    );

    System.assertEquals(1, snapshotsByEcProductId.size());
    System.assertEquals(
      JSON.serialize(new List<String>{ 'BG-1', 'BG-2' }),
      JSON.serialize(
        snapshotsByEcProductId.get('EC-MERGED').getSortedBuyerGroupIds()
      )
    );
  }

  @IsTest
  static void testFallbackProvider_handlesEmptyScopeGracefully() {
    Map<Id, CatalogBuyerGroupAccessSnapshot> snapshots = CatalogBuyerGroupAccessResolver.resolveBuyerGroupAccess(
      new CatalogJobConfig__mdt(),
      new List<Product2>(),
      new CatalogJsonBuilderLegacyTestStub()
    );

    System.assertEquals(0, snapshots.size());
  }

  @IsTest
  static void testGetProvider_returnsCustomAndFallbackProviders() {
    System.assertEquals(
      true,
      CatalogBuyerGroupAccessResolver.getProvider(
        new CustomAccessBuilder()
      ) instanceof CustomAccessBuilder
    );
    System.assertEquals(
      true,
      CatalogBuyerGroupAccessResolver.getProvider(
        new CatalogJobConfig__mdt(
          BuilderType__c = 'CatalogJsonBuilderLegacyTestStub'
        )
      ) instanceof CatalogBuyerGroupEntitlementProvider
    );
  }

  @IsTest
  static void testGetRequiredProductFields_returnsEmptyWhenProviderReturnsNull() {
    System.assertEquals(
      0,
      CatalogBuyerGroupAccessResolver.getRequiredProductFields(
          new NullFieldAccessBuilder()
        )
        .size()
    );
  }

  @IsTest
  static void testResolveBuyerGroupAccess_normalizesNullSetsAndSkipsMissingEcIds() {
    String webStoreId = String.valueOf(Id.valueOf('0ZE000000000003'));
    List<Product2> products = new List<Product2>{
      new Product2(
        Id = Id.valueOf('01t000000000221AAA'),
        ProductCode = 'EC-221'
      ),
      new Product2(
        Id = Id.valueOf('01t000000000222AAA'),
        ProductCode = 'EC-222'
      )
    };

    Map<Id, CatalogBuyerGroupAccessSnapshot> snapshots = CatalogBuyerGroupAccessResolver.resolveBuyerGroupAccess(
      new CatalogJobConfig__mdt(WebStoreId__c = webStoreId),
      products,
      new Map<Id, String>{ products[0].Id => 'EC-221' },
      new NullFieldAccessBuilder()
    );

    System.assertEquals(
      1,
      snapshots.size(),
      'Products without resolved ec_product_id values should be skipped during normalization'
    );
    System.assertEquals(
      0,
      snapshots.get(products[0].Id).buyerGroupIds.size(),
      'Null Buyer Group ids should normalize to an empty set'
    );
    System.assertEquals(
      0,
      snapshots.get(products[0].Id).buyerGroupNames.size(),
      'Null Buyer Group names should normalize to an empty set'
    );
    System.assertEquals(
      webStoreId,
      snapshots.get(products[0].Id).webStoreId,
      'Blank snapshot store values should fall back to the job config store'
    );
  }

  @IsTest
  static void testIndexSnapshotsByEcProductId_handlesNullAndBlankSnapshots() {
    String fallbackWebStoreId = String.valueOf(Id.valueOf('0ZE000000000004'));
    String snapshotWebStoreId = String.valueOf(Id.valueOf('0ZE000000000005'));
    System.assertEquals(
      0,
      CatalogBuyerGroupAccessResolver.indexSnapshotsByEcProductId(
          null,
          fallbackWebStoreId
        )
        .size()
    );

    CatalogBuyerGroupAccessSnapshot blankSnapshot = new CatalogBuyerGroupAccessSnapshot();
    blankSnapshot.productId = Id.valueOf('01t000000000231AAA');
    blankSnapshot.ecProductId = ' ';

    CatalogBuyerGroupAccessSnapshot validSnapshot = new CatalogBuyerGroupAccessSnapshot();
    validSnapshot.productId = Id.valueOf('01t000000000232AAA');
    validSnapshot.ecProductId = 'EC-232';
    validSnapshot.buyerGroupIds.add('BG-232');

    Map<String, CatalogBuyerGroupAccessSnapshot> indexedSnapshots = CatalogBuyerGroupAccessResolver.indexSnapshotsByEcProductId(
      new Map<Id, CatalogBuyerGroupAccessSnapshot>{
        blankSnapshot.productId => blankSnapshot,
        validSnapshot.productId => validSnapshot
      },
      snapshotWebStoreId
    );

    System.assertEquals(1, indexedSnapshots.size());
    System.assertEquals(
      snapshotWebStoreId,
      indexedSnapshots.get('EC-232').webStoreId
    );
  }
}
