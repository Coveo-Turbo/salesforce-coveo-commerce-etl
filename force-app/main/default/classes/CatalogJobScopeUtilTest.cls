@IsTest
private class CatalogJobScopeUtilTest {
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
}
