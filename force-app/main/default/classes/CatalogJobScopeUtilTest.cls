@IsTest
private class CatalogJobScopeUtilTest {
  private static Product2 createProduct(String code, String family) {
    Product2 product = new Product2(
      Name = 'Scope Util ' + code,
      ProductCode = code,
      Family = family,
      IsActive = true
    );
    insert product;
    return product;
  }

  private static ProductCatalog createCatalogWithProducts(List<Product2> products) {
    ProductCatalog catalog = new ProductCatalog(Name = 'Scope Util Catalog');
    insert catalog;

    ProductCategory category = new ProductCategory(
      Name = 'Scope Util Category',
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

  private static List<String> collectProductCodes(Database.QueryLocator locator) {
    List<String> productCodes = new List<String>();
    Database.QueryLocatorIterator iterator = locator.iterator();
    while (iterator.hasNext()) {
      Product2 product = (Product2) iterator.next();
      productCodes.add(product.ProductCode);
    }
    return productCodes;
  }

  @IsTest
  static void testGetExportedItemId_prefersProductCode() {
    Product2 product = new Product2(
      Id = Id.valueOf('01t000000000001AAA'),
      ProductCode = 'SKU-001'
    );

    System.assertEquals(
      'SKU-001',
      CatalogJobScopeUtil.getExportedItemId(product)
    );
  }

  @IsTest
  static void testGetExportedItemId_fallsBackToId() {
    Id productId = Id.valueOf('01t000000000002AAA');
    Product2 product = new Product2(Id = productId);

    System.assertEquals(
      String.valueOf(productId),
      CatalogJobScopeUtil.getExportedItemId(product)
    );
  }

  @IsTest
  static void testValidateAndSanitizeFilter_allowsSimpleFilter() {
    String sanitized = CatalogJobScopeUtil.validateAndSanitizeFilter(
      ' Family = \'Generators\' '
    );

    System.assertEquals('Family = \'Generators\'', sanitized);
  }

  @IsTest
  static void testValidateAndSanitizeFilter_blocksDmlKeyword() {
    Boolean exceptionThrown = false;

    try {
      CatalogJobScopeUtil.validateAndSanitizeFilter(
        'Family = \'Generators\' UPDATE Product2 SET Name = \'Bad\''
      );
    } catch (CatalogJobException ex) {
      exceptionThrown = true;
    }

    System.assertEquals(
      true,
      exceptionThrown,
      'DML keywords should be rejected'
    );
  }

  @IsTest
  static void testValidateAndSanitizeFilter_blocksSubqueryPattern() {
    Boolean exceptionThrown = false;

    try {
      CatalogJobScopeUtil.validateAndSanitizeFilter(
        'Id IN (SELECT ProductId FROM PricebookEntry)'
      );
    } catch (CatalogJobException ex) {
      exceptionThrown = true;
    }

    System.assertEquals(
      true,
      exceptionThrown,
      'Subquery patterns should be rejected'
    );
  }

  @IsTest
  static void testBuildProductQueryLocator_filtersByCatalogAndProductFilter() {
    Product2 matchingProduct = createProduct('SKU-GEN-001', 'Generators');
    Product2 filteredOutProduct = createProduct('SKU-TOOL-001', 'Tools');
    createProduct('SKU-OUT-001', 'Generators');
    ProductCatalog catalog = createCatalogWithProducts(
      new List<Product2>{ matchingProduct, filteredOutProduct }
    );

    CatalogJobConfig__mdt config = new CatalogJobConfig__mdt(
      DeveloperName = 'ScopeUtilLocator',
      MasterLabel = 'Scope Util Locator',
      CatalogId__c = String.valueOf(catalog.Id),
      ProductFilter__c = 'Family = \'Generators\''
    );

    Database.QueryLocator locator = CatalogJobScopeUtil.buildProductQueryLocator(
      config,
      new List<String>{ 'Id', 'ProductCode', 'Family' },
      new List<String>{ 'Name', 'ProductCode', 'Name' }
    );

    System.assertEquals(
      new List<String>{ 'SKU-GEN-001' },
      collectProductCodes(locator),
      'The query locator should keep only catalog-linked products that match the filter'
    );
  }

  @IsTest
  static void testBuildProductQueryLocator_returnsEmptyWhenCatalogHasNoProducts() {
    ProductCatalog emptyCatalog = new ProductCatalog(Name = 'Empty Scope Catalog');
    insert emptyCatalog;

    CatalogJobConfig__mdt config = new CatalogJobConfig__mdt(
      DeveloperName = 'EmptyScopeLocator',
      MasterLabel = 'Empty Scope Locator',
      CatalogId__c = String.valueOf(emptyCatalog.Id)
    );

    Database.QueryLocator locator = CatalogJobScopeUtil.buildProductQueryLocator(
      config,
      new List<String>{ 'Id', 'ProductCode' },
      null
    );

    System.assertEquals(
      0,
      collectProductCodes(locator).size(),
      'An empty catalog should produce an empty query locator'
    );
  }

  @IsTest
  static void testQueryProductsByIds_respectsCatalogFilterAndEmptyInputs() {
    Product2 matchingProduct = createProduct('SKU-GEN-010', 'Generators');
    Product2 filteredOutProduct = createProduct('SKU-TOOL-010', 'Tools');
    Product2 outsideCatalogProduct = createProduct('SKU-GEN-020', 'Generators');
    ProductCatalog catalog = createCatalogWithProducts(
      new List<Product2>{ matchingProduct, filteredOutProduct }
    );

    CatalogJobConfig__mdt config = new CatalogJobConfig__mdt(
      DeveloperName = 'ScopedProductQuery',
      MasterLabel = 'Scoped Product Query',
      CatalogId__c = String.valueOf(catalog.Id),
      ProductFilter__c = 'Family = \'Generators\''
    );

    List<Product2> scopedProducts = CatalogJobScopeUtil.queryProductsByIds(
      config,
      new Set<Id>{
        matchingProduct.Id,
        filteredOutProduct.Id,
        outsideCatalogProduct.Id
      },
      new List<String>{ 'Id', 'ProductCode', 'Family' }
    );

    System.assertEquals(1, scopedProducts.size());
    System.assertEquals('SKU-GEN-010', scopedProducts[0].ProductCode);

    System.assertEquals(
      0,
      CatalogJobScopeUtil.queryProductsByIds(
        config,
        new Set<Id>(),
        new List<String>{ 'Id' }
      ).size(),
      'Empty input sets should short-circuit without querying'
    );
  }
}
