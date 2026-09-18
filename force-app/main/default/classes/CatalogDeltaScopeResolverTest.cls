@IsTest
private class CatalogDeltaScopeResolverTest {
  private static CatalogJobConfig__mdt createConfig(String builderType) {
    return new CatalogJobConfig__mdt(
      DeveloperName = 'DELTA_SCOPE_TEST',
      MasterLabel = 'Delta Scope Test',
      CoveoOrgId__c = 'org-123',
      SourceId__c = 'source-456',
      Locale__c = 'en-US',
      BuilderType__c = builderType,
      SyncMode__c = 'Delta',
      BaselineFullConfigDeveloperName__c = 'FULL_SCOPE_TEST'
    );
  }

  private static Product2 createProduct(String code, String family) {
    Product2 product = new Product2(
      Name = 'Scope ' + code,
      ProductCode = code,
      Family = family,
      Description = 'Description ' + code,
      IsActive = true
    );
    insert product;
    return product;
  }

  private static ProductCatalog createCatalog(Product2 product) {
    ProductCatalog catalog = new ProductCatalog(Name = 'Delta Scope Catalog');
    insert catalog;

    ProductCategory category = new ProductCategory(
      Name = 'Delta Scope Category',
      CatalogId = catalog.Id
    );
    insert category;

    insert new ProductCategoryProduct(
      ProductId = product.Id,
      ProductCategoryId = category.Id
    );

    return catalog;
  }

  @IsTest
  static void testSynchronousScopeApisDirectCallersToPersistedPipeline() {
    Boolean resolutionRejected = false;
    try {
      CatalogDeltaScopeResolver.resolveExportProductIds(
        createConfig('Default'),
        System.now().addMinutes(-5),
        System.now()
      );
    } catch (CatalogJobException e) {
      resolutionRejected = e.getMessage().contains('persisted delta pipeline');
    }
    System.assertEquals(true, resolutionRejected);

    Boolean metricsRejected = false;
    try {
      CatalogDeltaScopeResolver.describeScope(
        createConfig('Default'),
        System.now().addMinutes(-5),
        System.now()
      );
    } catch (CatalogJobException e) {
      metricsRejected = e.getMessage().contains('getDeltaRunSnapshots');
    }
    System.assertEquals(true, metricsRejected);
  }

  @IsTest
  static void testResolveRootProductIds_commerceUsesChangedProductAsRoot() {
    Product2 product = createProduct('COMMERCE-001', 'Hardware');

    System.assertEquals(
      new Set<Id>{ product.Id },
      CatalogDeltaScopeResolver.resolveRootProductIds(
        createConfig('Commerce'),
        new Set<Id>{ product.Id }
      )
    );
  }

  @IsTest
  static void testResolveRootProductIds_groupingFallsBackWhenRelationshipFieldMissing() {
    Product2 parentProduct = createProduct('GROUP-001', 'Shoes');
    Product2 childProduct = createProduct('GROUP-002', 'Shoes');
    CatalogJobConfig__mdt config = createConfig('Grouping');

    if (
      !Product2.SObjectType.getDescribe().fields.getMap().containsKey('Parent_Product__c')
    ) {
      System.assertEquals(
        new Set<Id>{ childProduct.Id },
        CatalogDeltaScopeResolver.resolveRootProductIds(
          config,
          new Set<Id>{ childProduct.Id }
        )
      );
      return;
    }

    childProduct.put('Parent_Product__c', parentProduct.Id);
    update childProduct;

    Set<Id> rootIds = CatalogDeltaScopeResolver.resolveRootProductIds(
      config,
      new Set<Id>{ childProduct.Id }
    );

    System.assertEquals(new Set<Id>{ parentProduct.Id }, rootIds);
  }

  @IsTest
  static void testResolveRootProductIds_variantUsesTopAncestor() {
    if (
      !Product2.SObjectType.getDescribe().fields.getMap().containsKey('Parent_Product__c')
    ) {
      System.assert(true, 'Parent_Product__c is not available in this org');
      return;
    }

    Product2 rootProduct = createProduct('VARIANT-ROOT', 'Shoes');
    Product2 variantProduct = createProduct('VARIANT-CHILD', 'Shoes');
    variantProduct.put('Parent_Product__c', rootProduct.Id);
    update variantProduct;

    System.assertEquals(
      new Set<Id>{ rootProduct.Id },
      CatalogDeltaScopeResolver.resolveRootProductIds(
        createConfig('Variant'),
        new Set<Id>{ variantProduct.Id }
      )
    );
  }

  @IsTest
  static void testResolveRootProductIds_groupingWithVariantsPrefersProductGroup() {
    Map<String, SObjectField> productFields = Product2.SObjectType.getDescribe()
      .fields.getMap();
    if (
      !productFields.containsKey('Parent_Product__c') ||
      !productFields.containsKey('Product_Group__c')
    ) {
      System.assert(true, 'GroupingWithVariants fields are not available in this org');
      return;
    }

    Product2 groupProduct = createProduct('GROUP-ROOT', 'Shoes');
    Product2 childProduct = createProduct('GROUP-CHILD', 'Shoes');
    childProduct.put('Parent_Product__c', groupProduct.Id);
    childProduct.put('Product_Group__c', groupProduct.Id);
    update childProduct;

    System.assertEquals(
      new Set<Id>{ groupProduct.Id },
      CatalogDeltaScopeResolver.resolveRootProductIds(
        createConfig('GroupingWithVariants'),
        new Set<Id>{ childProduct.Id }
      )
    );
  }
}
