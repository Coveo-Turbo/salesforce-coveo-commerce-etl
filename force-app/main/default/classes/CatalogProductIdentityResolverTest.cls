@IsTest
private class CatalogProductIdentityResolverTest {
  private class MissingIdentityProvider
    implements ICatalogJsonBuilder, ICatalogProductIdentityProvider {
    public List<String> getRequiredProductFieldsForIdentity() {
      return new List<String>{ 'ProductCode' };
    }

    public Map<Id, String> resolveEcProductIds(List<Product2> products) {
      return new Map<Id, String>();
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
  static void testGetRequiredProductFields_fallbackUsesProductCode() {
    List<String> requiredFields =
      CatalogProductIdentityResolver.getRequiredProductFields(
        new CatalogJsonBuilderLegacyTestStub()
      );

    System.assertEquals(
      new List<String>{ 'Id', 'ProductCode' },
      requiredFields
    );
  }

  @IsTest
  static void testGetRequiredProductFields_providerUsesCustomFields() {
    List<String> requiredFields =
      CatalogProductIdentityResolver.getRequiredProductFields(
        new CatalogJsonBuilderCreatedByIdStub()
      );

    System.assertEquals(
      new List<String>{ 'Id', 'CreatedById' },
      requiredFields
    );
  }

  @IsTest
  static void testResolveEcProductIds_fallbackPrefersProductCode() {
    Product2 productWithCode = new Product2(
      Id = Id.valueOf('01t000000000101AAA'),
      ProductCode = 'SKU-101'
    );
    Product2 productWithoutCode = new Product2(
      Id = Id.valueOf('01t000000000102AAA')
    );

    Map<Id, String> resolvedIds = CatalogProductIdentityResolver.resolveEcProductIds(
      new CatalogJsonBuilderLegacyTestStub(),
      new List<Product2>{ productWithCode, productWithoutCode }
    );

    System.assertEquals('SKU-101', resolvedIds.get(productWithCode.Id));
    System.assertEquals(
      String.valueOf(productWithoutCode.Id),
      resolvedIds.get(productWithoutCode.Id)
    );
  }

  @IsTest
  static void testResolveEcProductIds_providerUsesStockKeepingUnit() {
    Product2 product = new Product2(
      Id = Id.valueOf('01t000000000103AAA'),
      ProductCode = 'SKU-103',
      StockKeepingUnit = 'STOCK-103'
    );

    Map<Id, String> resolvedIds = CatalogProductIdentityResolver.resolveEcProductIds(
      new CatalogJsonBuilderSkuIdentityStub(),
      new List<Product2>{ product }
    );

    System.assertEquals('STOCK-103', resolvedIds.get(product.Id));
  }

  @IsTest
  static void testResolveEcProductIds_rejectsMissingProviderValue() {
    Product2 product = new Product2(Id = Id.valueOf('01t000000000104AAA'));

    Boolean failed = false;
    try {
      CatalogProductIdentityResolver.resolveEcProductIds(
        new MissingIdentityProvider(),
        new List<Product2>{ product }
      );
    } catch (CatalogJobException ex) {
      failed = true;
      System.assert(ex.getMessage().contains('did not return'));
    }

    System.assertEquals(true, failed);
  }

  @IsTest
  static void testResolveEcProductIds_rejectsBlankProviderValue() {
    Product2 product = new Product2(
      Id = Id.valueOf('01t000000000105AAA'),
      ProductCode = 'SKU-105'
    );

    Boolean failed = false;
    try {
      CatalogProductIdentityResolver.resolveEcProductIds(
        new CatalogJsonBuilderBrokenIdentityTestStub(),
        new List<Product2>{ product }
      );
    } catch (CatalogJobException ex) {
      failed = true;
      System.assert(ex.getMessage().contains('blank ec_product_id'));
    }

    System.assertEquals(true, failed);
  }
}
