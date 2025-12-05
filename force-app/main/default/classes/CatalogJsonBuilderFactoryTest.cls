@IsTest
private class CatalogJsonBuilderFactoryTest {
  /**
   * Tests the getForBuilderType method with various builder type names.
   */
  @IsTest
  static void testGetForBuilderType_Default() {
    Test.startTest();
    ICatalogJsonBuilder builder = CatalogJsonBuilderFactory.getForBuilderType(
      'Default'
    );
    Test.stopTest();

    System.assertNotEquals(null, builder, 'Builder should not be null');
    System.assert(
      builder instanceof CatalogJsonBuilderDefault,
      'Builder should be CatalogJsonBuilderDefault'
    );
  }

  @IsTest
  static void testGetForBuilderType_Commerce() {
    Test.startTest();
    ICatalogJsonBuilder builder = CatalogJsonBuilderFactory.getForBuilderType(
      'Commerce'
    );
    Test.stopTest();

    System.assertNotEquals(null, builder, 'Builder should not be null');
    System.assert(
      builder instanceof CatalogJsonBuilderCommerce,
      'Builder should be CatalogJsonBuilderCommerce'
    );
  }

  @IsTest
  static void testGetForBuilderType_Grouping() {
    Test.startTest();
    ICatalogJsonBuilder builder = CatalogJsonBuilderFactory.getForBuilderType(
      'Grouping'
    );
    Test.stopTest();

    System.assertNotEquals(null, builder, 'Builder should not be null');
    System.assert(
      builder instanceof CatalogJsonBuilderGrouping,
      'Builder should be CatalogJsonBuilderGrouping'
    );
  }

  @IsTest
  static void testGetForBuilderType_Variant() {
    Test.startTest();
    ICatalogJsonBuilder builder = CatalogJsonBuilderFactory.getForBuilderType(
      'Variant'
    );
    Test.stopTest();

    System.assertNotEquals(null, builder, 'Builder should not be null');
    System.assert(
      builder instanceof CatalogJsonBuilderVariant,
      'Builder should be CatalogJsonBuilderVariant'
    );
  }

  @IsTest
  static void testGetForBuilderType_GroupingWithVariants() {
    Test.startTest();
    ICatalogJsonBuilder builder = CatalogJsonBuilderFactory.getForBuilderType(
      'GroupingWithVariants'
    );
    Test.stopTest();

    System.assertNotEquals(null, builder, 'Builder should not be null');
    System.assert(
      builder instanceof CatalogJsonBuilderGroupingWithVariants,
      'Builder should be CatalogJsonBuilderGroupingWithVariants'
    );
  }

  @IsTest
  static void testGetForBuilderType_CaseInsensitive() {
    Test.startTest();
    ICatalogJsonBuilder builder1 = CatalogJsonBuilderFactory.getForBuilderType(
      'default'
    );
    ICatalogJsonBuilder builder2 = CatalogJsonBuilderFactory.getForBuilderType(
      'DEFAULT'
    );
    ICatalogJsonBuilder builder3 = CatalogJsonBuilderFactory.getForBuilderType(
      'Default'
    );
    Test.stopTest();

    System.assert(
      builder1 instanceof CatalogJsonBuilderDefault,
      'lowercase should work'
    );
    System.assert(
      builder2 instanceof CatalogJsonBuilderDefault,
      'uppercase should work'
    );
    System.assert(
      builder3 instanceof CatalogJsonBuilderDefault,
      'mixed case should work'
    );
  }

  @IsTest
  static void testGetForBuilderType_NullFallsBackToGlobal() {
    Test.startTest();
    ICatalogJsonBuilder builder = CatalogJsonBuilderFactory.getForBuilderType(
      null
    );
    Test.stopTest();

    // Should fall back to global default (Commerce by default)
    System.assertNotEquals(null, builder, 'Builder should not be null');
  }

  @IsTest
  static void testGetForBuilderType_EmptyFallsBackToGlobal() {
    Test.startTest();
    ICatalogJsonBuilder builder = CatalogJsonBuilderFactory.getForBuilderType(
      ''
    );
    Test.stopTest();

    System.assertNotEquals(null, builder, 'Builder should not be null');
  }

  @IsTest
  static void testGetForBuilderType_FullClassName() {
    Test.startTest();
    ICatalogJsonBuilder builder = CatalogJsonBuilderFactory.getForBuilderType(
      'CatalogJsonBuilderDefault'
    );
    Test.stopTest();

    System.assertNotEquals(null, builder, 'Builder should not be null');
    System.assert(
      builder instanceof CatalogJsonBuilderDefault,
      'Full class name should work'
    );
  }

  @IsTest
  static void testGet_ReturnsBuilder() {
    Test.startTest();
    ICatalogJsonBuilder builder = CatalogJsonBuilderFactory.get();
    Test.stopTest();

    System.assertNotEquals(null, builder, 'Builder should not be null');
  }

  @IsTest
  static void testGetAvailableBuilderTypes() {
    Test.startTest();
    List<Map<String, String>> types = CatalogJsonBuilderFactory.getAvailableBuilderTypes();
    Test.stopTest();

    System.assertEquals(5, types.size(), 'Should return 5 builder types');

    Set<String> values = new Set<String>();
    for (Map<String, String> t : types) {
      values.add(t.get('value'));
      System.assertNotEquals(
        null,
        t.get('label'),
        'Each type should have a label'
      );
    }

    System.assert(values.contains('Default'), 'Should include Default');
    System.assert(values.contains('Commerce'), 'Should include Commerce');
    System.assert(values.contains('Grouping'), 'Should include Grouping');
    System.assert(values.contains('Variant'), 'Should include Variant');
    System.assert(
      values.contains('GroupingWithVariants'),
      'Should include GroupingWithVariants'
    );
  }

  @IsTest
  static void testGetForBuilderType_UnknownClassThrowsException() {
    Boolean exceptionThrown = false;

    Test.startTest();
    try {
      CatalogJsonBuilderFactory.getForBuilderType(
        'NonExistentBuilderClass12345'
      );
    } catch (AuraHandledException e) {
      exceptionThrown = true;
      System.assert(
        e.getMessage().contains('Unknown builder class'),
        'Exception message should mention unknown class'
      );
    }
    Test.stopTest();

    System.assert(exceptionThrown, 'Should throw exception for unknown class');
  }
}
