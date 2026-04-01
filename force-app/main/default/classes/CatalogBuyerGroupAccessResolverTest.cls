@IsTest
private class CatalogBuyerGroupAccessResolverTest {
  private class CustomAccessBuilder
    implements
      ICatalogJsonBuilder,
      ICatalogProductIdentityProvider,
      ICatalogBuyerGroupAccessProvider {
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
      Map<Id, CatalogBuyerGroupAccessSnapshot> snapshots =
        new Map<Id, CatalogBuyerGroupAccessSnapshot>();

      if (products.isEmpty()) {
        return snapshots;
      }

      Product2 firstProduct = products[0];
      CatalogBuyerGroupAccessSnapshot snapshot =
        new CatalogBuyerGroupAccessSnapshot();
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
      WebStoreId__c = 'web-store-1'
    );

    Map<Id, CatalogBuyerGroupAccessSnapshot> snapshots =
      CatalogBuyerGroupAccessResolver.resolveBuyerGroupAccess(
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
    System.assertEquals(
      'web-store-1',
      snapshots.get(products[1].Id).webStoreId
    );
  }

  @IsTest
  static void testIndexSnapshotsByEcProductId_mergesMemberships() {
    CatalogBuyerGroupAccessSnapshot firstSnapshot =
      new CatalogBuyerGroupAccessSnapshot();
    firstSnapshot.productId = Id.valueOf('01t000000000211AAA');
    firstSnapshot.ecProductId = 'EC-MERGED';
    firstSnapshot.webStoreId = 'store-1';
    firstSnapshot.buyerGroupIds.add('BG-2');
    firstSnapshot.buyerGroupNames.add('Beta');

    CatalogBuyerGroupAccessSnapshot secondSnapshot =
      new CatalogBuyerGroupAccessSnapshot();
    secondSnapshot.productId = Id.valueOf('01t000000000212AAA');
    secondSnapshot.ecProductId = 'EC-MERGED';
    secondSnapshot.webStoreId = 'store-1';
    secondSnapshot.buyerGroupIds.add('BG-1');
    secondSnapshot.buyerGroupNames.add('Alpha');

    Map<String, CatalogBuyerGroupAccessSnapshot> snapshotsByEcProductId =
      CatalogBuyerGroupAccessResolver.indexSnapshotsByEcProductId(
        new Map<Id, CatalogBuyerGroupAccessSnapshot>{
          firstSnapshot.productId => firstSnapshot,
          secondSnapshot.productId => secondSnapshot
        },
        'store-1'
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
    Map<Id, CatalogBuyerGroupAccessSnapshot> snapshots =
      CatalogBuyerGroupAccessResolver.resolveBuyerGroupAccess(
        new CatalogJobConfig__mdt(),
        new List<Product2>(),
        new CatalogJsonBuilderLegacyTestStub()
      );

    System.assertEquals(0, snapshots.size());
  }
}
