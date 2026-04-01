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

  private class NullFieldIdentityProvider
    implements ICatalogJsonBuilder, ICatalogProductIdentityProvider {
    public List<String> getRequiredProductFieldsForIdentity() {
      return new List<String>{ null, ' ', 'ProductCode', ' ProductCode ' };
    }

    public Map<Id, String> resolveEcProductIds(List<Product2> products) {
      Map<Id, String> resolvedIds = new Map<Id, String>();
      for (Product2 product : products) {
        if (product != null && product.Id != null) {
          resolvedIds.put(product.Id, 'EC-' + product.Id);
        }
      }
      return resolvedIds;
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

  private class NullListIdentityProvider
    implements ICatalogJsonBuilder, ICatalogProductIdentityProvider {
    public List<String> getRequiredProductFieldsForIdentity() {
      return null;
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

  @IsTest
  static void testSupportsBuilderDrivenIdentity_coversBuilderStringAndConfigPaths() {
    System.assertEquals(
      true,
      CatalogProductIdentityResolver.supportsBuilderDrivenIdentity(
        new CatalogJobConfig__mdt(
          BuilderType__c = 'CatalogJsonBuilderCreatedByIdStub'
        )
      )
    );
    System.assertEquals(
      true,
      CatalogProductIdentityResolver.supportsBuilderDrivenIdentity(
        'CatalogJsonBuilderSkuIdentityStub'
      )
    );
    System.assertEquals(
      false,
      CatalogProductIdentityResolver.supportsBuilderDrivenIdentity(
        (ICatalogJsonBuilder) new CatalogJsonBuilderLegacyTestStub()
      )
    );
  }

  @IsTest
  static void testGetRequiredProductFields_handlesNullAndBlankProviderFields() {
    System.assertEquals(
      new List<String>{ 'Id', 'ProductCode' },
      CatalogProductIdentityResolver.getRequiredProductFields(
        new NullFieldIdentityProvider()
      ),
      'Provider-required fields should be trimmed, deduplicated, and ignore blanks'
    );
    System.assertEquals(
      new List<String>{ 'Id' },
      CatalogProductIdentityResolver.getRequiredProductFields(
        new NullListIdentityProvider()
      ),
      'A null provider field list should fall back to only Id'
    );
  }

  @IsTest
  static void testResolveEcProductIds_handlesNullEmptyAndMissingIds() {
    System.assertEquals(
      0,
      CatalogProductIdentityResolver.resolveEcProductIds(
        new CatalogJsonBuilderLegacyTestStub(),
        new List<Product2>()
      ).size(),
      'Empty product scopes should resolve to an empty identity map'
    );
    System.assertEquals(
      0,
      CatalogProductIdentityResolver.resolveFallbackEcProductIds(null).size(),
      'Null fallback inputs should resolve to an empty identity map'
    );

    Boolean fallbackFailed = false;
    try {
      CatalogProductIdentityResolver.resolveFallbackEcProductIds(
        new List<Product2>{ new Product2(ProductCode = 'NO-ID') }
      );
    } catch (CatalogJobException ex) {
      fallbackFailed = true;
      System.assert(ex.getMessage().contains('requires every product to include an Id'));
    }
    System.assertEquals(
      true,
      fallbackFailed,
      'Fallback identity resolution should reject products without Id values'
    );

    Boolean providerFailed = false;
    try {
      CatalogProductIdentityResolver.resolveEcProductIds(
        new NullFieldIdentityProvider(),
        new List<Product2>{ new Product2(ProductCode = 'NO-ID') }
      );
    } catch (CatalogJobException ex) {
      providerFailed = true;
      System.assert(ex.getMessage().contains('requires every product to include an Id'));
    }
    System.assertEquals(
      true,
      providerFailed,
      'Provider-driven identity resolution should reject products without Id values'
    );
  }
}
