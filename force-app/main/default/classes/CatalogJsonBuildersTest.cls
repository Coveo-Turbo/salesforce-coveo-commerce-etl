@IsTest
private class CatalogJsonBuildersTest {
  /**
   * Helper method to create test products.
   */
  private static List<Product2> createTestProducts() {
    List<Product2> products = new List<Product2>();

    // Parent/Base product
    products.add(
      new Product2(
        Name = 'Test Parent Product',
        ProductCode = 'PARENT-001',
        Description = 'A test parent product',
        Family = 'Electronics',
        IsActive = true
      )
    );

    // Another product
    products.add(
      new Product2(
        Name = 'Test Simple Product',
        ProductCode = 'SIMPLE-001',
        Description = 'A simple product',
        Family = 'Apparel',
        IsActive = true
      )
    );

    return products;
  }

  /**
   * Tests CatalogJsonBuilderDefault with a simple product.
   */
  @IsTest
  static void testDefaultBuilder_buildFullUpdateNdjson() {
    List<Product2> products = createTestProducts();

    Map<Id, PricebookEntry> emptyPbeMap = new Map<Id, PricebookEntry>();

    CatalogJsonBuilderDefault builder = new CatalogJsonBuilderDefault();

    Test.startTest();
    String json = builder.buildFullUpdateNdjson(products, emptyPbeMap, null);
    Test.stopTest();

    System.assertNotEquals(null, json, 'JSON should not be null');
    System.assert(
      json.contains('addOrUpdate'),
      'Should contain addOrUpdate key'
    );
    System.assert(json.contains('PARENT-001'), 'Should contain product code');
    System.assert(
      json.contains('Test Parent Product'),
      'Should contain product name'
    );
    System.assert(
      json.contains('ec_product_id'),
      'Should contain ec_product_id'
    );
    System.assert(json.contains('ec_category'), 'Should contain ec_category');
  }

  @IsTest
  static void testDefaultBuilder_buildPartialMergeNdjson() {
    Map<String, Decimal> priceMap = new Map<String, Decimal>{
      'SKU-001' => 99.99,
      'SKU-002' => 149.99
    };

    Map<String, Boolean> stockMap = new Map<String, Boolean>{
      'SKU-001' => true,
      'SKU-002' => false
    };

    CatalogJsonBuilderDefault builder = new CatalogJsonBuilderDefault();

    Test.startTest();
    String json = builder.buildPartialMergeNdjson(priceMap, stockMap);
    Test.stopTest();

    System.assert(json.contains('addOrMerge'), 'Should contain addOrMerge key');
    System.assert(json.contains('SKU-001'), 'Should contain SKU-001');
    System.assert(json.contains('ec_price'), 'Should contain ec_price');
    System.assert(json.contains('ec_in_stock'), 'Should contain ec_in_stock');
  }

  @IsTest
  static void testDefaultBuilder_emptyProducts() {
    CatalogJsonBuilderDefault builder = new CatalogJsonBuilderDefault();

    Test.startTest();
    String json = builder.buildFullUpdateNdjson(
      new List<Product2>(),
      new Map<Id, PricebookEntry>(),
      null
    );
    Test.stopTest();

    System.assert(
      json.contains('addOrUpdate'),
      'Should contain addOrUpdate key'
    );
    System.assert(json.contains('[]'), 'Should contain empty array');
  }

  /**
   * Tests CatalogJsonBuilderGrouping
   */
  @IsTest
  static void testGroupingBuilder_buildFullUpdateNdjson() {
    List<Product2> products = createTestProducts();

    Map<Id, PricebookEntry> emptyPbeMap = new Map<Id, PricebookEntry>();

    CatalogJsonBuilderGrouping builder = new CatalogJsonBuilderGrouping();

    Test.startTest();
    String json = builder.buildFullUpdateNdjson(products, emptyPbeMap, null);
    Test.stopTest();

    System.assertNotEquals(null, json, 'JSON should not be null');
    System.assert(
      json.contains('addOrUpdate'),
      'Should contain addOrUpdate key'
    );
    System.assert(
      json.contains('ec_item_group_id'),
      'Should contain ec_item_group_id'
    );
    System.assert(json.contains('PARENT-001'), 'Should contain product code');
  }

  @IsTest
  static void testGroupingBuilder_buildPartialMergeNdjson() {
    Map<String, Decimal> priceMap = new Map<String, Decimal>{
      'SKU-001' => 99.99
    };

    CatalogJsonBuilderGrouping builder = new CatalogJsonBuilderGrouping();

    Test.startTest();
    String json = builder.buildPartialMergeNdjson(priceMap, null);
    Test.stopTest();

    System.assert(json.contains('addOrMerge'), 'Should contain addOrMerge key');
    System.assert(json.contains('SKU-001'), 'Should contain SKU');
  }

  @IsTest
  static void testGroupingBuilder_emptyProducts() {
    CatalogJsonBuilderGrouping builder = new CatalogJsonBuilderGrouping();

    Test.startTest();
    String json = builder.buildFullUpdateNdjson(
      new List<Product2>(),
      new Map<Id, PricebookEntry>(),
      null
    );
    Test.stopTest();

    System.assert(
      json.contains('addOrUpdate'),
      'Should contain addOrUpdate key'
    );
  }

  /**
   * Tests CatalogJsonBuilderVariant
   */
  @IsTest
  static void testVariantBuilder_buildFullUpdateNdjson() {
    List<Product2> products = createTestProducts();

    Map<Id, PricebookEntry> emptyPbeMap = new Map<Id, PricebookEntry>();

    CatalogJsonBuilderVariant builder = new CatalogJsonBuilderVariant();

    Test.startTest();
    String json = builder.buildFullUpdateNdjson(products, emptyPbeMap, null);
    Test.stopTest();

    System.assertNotEquals(null, json, 'JSON should not be null');
    System.assert(
      json.contains('addOrUpdate'),
      'Should contain addOrUpdate key'
    );
    System.assert(
      json.contains('ec_item_group_id'),
      'Should contain ec_item_group_id'
    );
    System.assert(json.contains('PARENT-001'), 'Should contain product code');
  }

  @IsTest
  static void testVariantBuilder_buildPartialMergeNdjson() {
    Map<String, Boolean> stockMap = new Map<String, Boolean>{
      'SKU-001' => true
    };

    CatalogJsonBuilderVariant builder = new CatalogJsonBuilderVariant();

    Test.startTest();
    String json = builder.buildPartialMergeNdjson(null, stockMap);
    Test.stopTest();

    System.assert(json.contains('addOrMerge'), 'Should contain addOrMerge key');
    System.assert(json.contains('SKU-001'), 'Should contain SKU');
    System.assert(json.contains('ec_in_stock'), 'Should contain ec_in_stock');
  }

  @IsTest
  static void testVariantBuilder_emptyProducts() {
    CatalogJsonBuilderVariant builder = new CatalogJsonBuilderVariant();

    Test.startTest();
    String json = builder.buildFullUpdateNdjson(
      new List<Product2>(),
      new Map<Id, PricebookEntry>(),
      null
    );
    Test.stopTest();

    System.assert(
      json.contains('addOrUpdate'),
      'Should contain addOrUpdate key'
    );
  }

  /**
   * Tests CatalogJsonBuilderGroupingWithVariants
   */
  @IsTest
  static void testGroupingWithVariantsBuilder_buildFullUpdateNdjson() {
    List<Product2> products = createTestProducts();

    Map<Id, PricebookEntry> emptyPbeMap = new Map<Id, PricebookEntry>();

    CatalogJsonBuilderGroupingWithVariants builder = new CatalogJsonBuilderGroupingWithVariants();

    Test.startTest();
    String json = builder.buildFullUpdateNdjson(products, emptyPbeMap, null);
    Test.stopTest();

    System.assertNotEquals(null, json, 'JSON should not be null');
    System.assert(
      json.contains('addOrUpdate'),
      'Should contain addOrUpdate key'
    );
    System.assert(
      json.contains('ec_item_group_id'),
      'Should contain ec_item_group_id'
    );
    System.assert(json.contains('PARENT-001'), 'Should contain product code');
  }

  @IsTest
  static void testGroupingWithVariantsBuilder_buildPartialMergeNdjson() {
    Map<String, Decimal> priceMap = new Map<String, Decimal>{
      'SKU-001' => 199.99
    };
    Map<String, Boolean> stockMap = new Map<String, Boolean>{
      'SKU-001' => false
    };

    CatalogJsonBuilderGroupingWithVariants builder = new CatalogJsonBuilderGroupingWithVariants();

    Test.startTest();
    String json = builder.buildPartialMergeNdjson(priceMap, stockMap);
    Test.stopTest();

    System.assert(json.contains('addOrMerge'), 'Should contain addOrMerge key');
    System.assert(json.contains('SKU-001'), 'Should contain SKU');
    System.assert(json.contains('ec_price'), 'Should contain ec_price');
    System.assert(json.contains('ec_in_stock'), 'Should contain ec_in_stock');
  }

  @IsTest
  static void testGroupingWithVariantsBuilder_emptyProducts() {
    CatalogJsonBuilderGroupingWithVariants builder = new CatalogJsonBuilderGroupingWithVariants();

    Test.startTest();
    String json = builder.buildFullUpdateNdjson(
      new List<Product2>(),
      new Map<Id, PricebookEntry>(),
      null
    );
    Test.stopTest();

    System.assert(
      json.contains('addOrUpdate'),
      'Should contain addOrUpdate key'
    );
  }

  /**
   * Tests that all builders implement ICatalogJsonBuilder interface
   */
  @IsTest
  static void testAllBuildersImplementInterface() {
    ICatalogJsonBuilder defaultBuilder = new CatalogJsonBuilderDefault();
    ICatalogJsonBuilder groupingBuilder = new CatalogJsonBuilderGrouping();
    ICatalogJsonBuilder variantBuilder = new CatalogJsonBuilderVariant();
    ICatalogJsonBuilder combinedBuilder = new CatalogJsonBuilderGroupingWithVariants();

    List<Product2> products = createTestProducts();
    Map<Id, PricebookEntry> pbeMap = new Map<Id, PricebookEntry>();
    List<String> extraFields = new List<String>();

    Test.startTest();

    // All should produce valid JSON
    String json1 = defaultBuilder.buildFullUpdateNdjson(
      products,
      pbeMap,
      extraFields
    );
    String json2 = groupingBuilder.buildFullUpdateNdjson(
      products,
      pbeMap,
      extraFields
    );
    String json3 = variantBuilder.buildFullUpdateNdjson(
      products,
      pbeMap,
      extraFields
    );
    String json4 = combinedBuilder.buildFullUpdateNdjson(
      products,
      pbeMap,
      extraFields
    );

    Test.stopTest();

    // Validate all produce non-null JSON with expected structure
    for (String json : new List<String>{ json1, json2, json3, json4 }) {
      System.assertNotEquals(null, json, 'JSON should not be null');
      System.assert(
        json.contains('addOrUpdate'),
        'Should contain addOrUpdate key'
      );
    }
  }

  /**
   * Tests extra field handling
   */
  @IsTest
  static void testBuildersWithExtraFields() {
    List<Product2> products = createTestProducts();
    Map<Id, PricebookEntry> pbeMap = new Map<Id, PricebookEntry>();
    List<String> extraFields = new List<String>{ 'Description', 'Family' };

    CatalogJsonBuilderDefault builder = new CatalogJsonBuilderDefault();

    Test.startTest();
    String json = builder.buildFullUpdateNdjson(products, pbeMap, extraFields);
    Test.stopTest();

    // Should include extra fields with sf_ prefix
    System.assert(
      json.contains('sf_description') || json.contains('sf_family'),
      'Should include extra fields with sf_ prefix'
    );
  }

  /**
   * Tests category fallback behavior
   */
  @IsTest
  static void testCategoryFallback() {
    // Product with Family set
    Product2 withFamily = new Product2(
      Name = 'With Family',
      ProductCode = 'WITH-FAM-001',
      Family = 'TestCategory',
      IsActive = true
    );

    // Product without Family
    Product2 withoutFamily = new Product2(
      Name = 'Without Family',
      ProductCode = 'NO-FAM-001',
      IsActive = true
    );

    List<Product2> products = new List<Product2>{ withFamily, withoutFamily };

    CatalogJsonBuilderDefault builder = new CatalogJsonBuilderDefault();

    Test.startTest();
    String json = builder.buildFullUpdateNdjson(
      products,
      new Map<Id, PricebookEntry>(),
      null
    );
    Test.stopTest();

    System.assert(
      json.contains('TestCategory'),
      'Should include Family as category'
    );
    System.assert(
      json.contains('Uncategorized'),
      'Should fallback to Uncategorized'
    );
  }
}
