@IsTest
private class WebStorePricebookResolverTest {
  @IsTest
  static void resolvesExplicitPricebooksWithRawIdLabels() {
    Pricebook2 firstPricebook = new Pricebook2(
      Name = 'Retail USD',
      IsActive = true
    );
    Pricebook2 secondPricebook = new Pricebook2(
      Name = 'Wholesale USD',
      IsActive = true
    );
    insert new List<Pricebook2>{ firstPricebook, secondPricebook };

    CatalogJobConfig__mdt config = new CatalogJobConfig__mdt(
      PricebookIds__c = String.valueOf(secondPricebook.Id) +
        ', ' +
        String.valueOf(firstPricebook.Id)
    );

    WebStorePricebookResolver.PricebookResolution resolution = WebStorePricebookResolver.resolve(
      config
    );

    System.assertEquals(true, resolution.isFiltered);
    System.assertEquals(
      new Set<Id>{ firstPricebook.Id, secondPricebook.Id },
      resolution.pricebookIds
    );
    System.assertEquals(
      String.valueOf(firstPricebook.Id),
      resolution.labelsByPricebookId.get(firstPricebook.Id)
    );
    System.assertEquals(
      String.valueOf(secondPricebook.Id),
      resolution.labelsByPricebookId.get(secondPricebook.Id)
    );
    Id sellingModelId = Id.valueOf('0jP000000000001');
    System.assertEquals(
      String.valueOf(firstPricebook.Id) + ':' + String.valueOf(sellingModelId),
      CatalogProductExportSupport.buildUniquePriceKey(
        new Map<String, Decimal>(),
        resolution.labelsByPricebookId.get(firstPricebook.Id),
        sellingModelId,
        firstPricebook.Id,
        Id.valueOf('01u000000000001')
      )
    );
  }

  @IsTest
  static void resolvesWebStorePricebooksWithRawIdLabels() {
    Pricebook2 pricebook = new Pricebook2(Name = 'USD', IsActive = true);
    insert pricebook;
    Id webStoreId = Id.valueOf('0ZE000000000001');
    WebStorePricebookResolver.testPricebooksByWebStoreIds = new Map<Id, String>{
      pricebook.Id => 'Brand A'
    };

    WebStorePricebookResolver.PricebookResolution resolution = WebStorePricebookResolver.resolve(
      new CatalogJobConfig__mdt(WebStoreIds__c = String.valueOf(webStoreId))
    );

    System.assertEquals(new Set<Id>{ pricebook.Id }, resolution.pricebookIds);
    System.assertEquals(
      String.valueOf(pricebook.Id),
      resolution.labelsByPricebookId.get(pricebook.Id)
    );
    Id sellingModelId = Id.valueOf('0jP000000000001');
    System.assertEquals(
      String.valueOf(pricebook.Id) + ':' + String.valueOf(sellingModelId),
      CatalogProductExportSupport.buildUniquePriceKey(
        new Map<String, Decimal>(),
        resolution.labelsByPricebookId.get(pricebook.Id),
        sellingModelId,
        pricebook.Id,
        Id.valueOf('01u000000000001')
      )
    );
  }

  @IsTest
  static void explicitPricebooksTakePrecedenceAndRemainRaw() {
    Pricebook2 explicitPricebook = new Pricebook2(
      Name = 'Retail',
      IsActive = true
    );
    Pricebook2 storePricebook = new Pricebook2(
      Name = 'Store Retail',
      IsActive = true
    );
    insert new List<Pricebook2>{ explicitPricebook, storePricebook };
    Id webStoreId = Id.valueOf('0ZE000000000001');
    WebStorePricebookResolver.testPricebooksByWebStoreIds = new Map<Id, String>{
      storePricebook.Id => 'Store A'
    };

    WebStorePricebookResolver.PricebookResolution resolution = WebStorePricebookResolver.resolve(
      new CatalogJobConfig__mdt(
        PricebookIds__c = String.valueOf(explicitPricebook.Id),
        WebStoreIds__c = String.valueOf(webStoreId)
      )
    );

    System.assertEquals(
      new Set<Id>{ explicitPricebook.Id },
      resolution.pricebookIds
    );
    System.assertEquals(
      String.valueOf(explicitPricebook.Id),
      resolution.labelsByPricebookId.get(explicitPricebook.Id)
    );
    System.assertEquals(
      false,
      resolution.pricebookIds.contains(storePricebook.Id)
    );
  }

  @IsTest
  static void preservesLegacyUnfilteredBehaviorWhenFieldsAreBlank() {
    WebStorePricebookResolver.PricebookResolution resolution = WebStorePricebookResolver.resolve(
      new CatalogJobConfig__mdt()
    );

    System.assertEquals(false, resolution.isFiltered);
    System.assertEquals(null, resolution.pricebookIds);
    System.assertEquals(null, resolution.labelsByPricebookId);
  }

  @IsTest
  static void rejectsInvalidConfiguredIds() {
    try {
      WebStorePricebookResolver.resolve(
        new CatalogJobConfig__mdt(PricebookIds__c = 'not-an-id')
      );
      System.assert(false, 'Expected invalid ID validation to fail.');
    } catch (CatalogJobConfigException e) {
      System.assert(e.getMessage().contains('PricebookIds__c'));
    }
  }

  @IsTest
  static void filtersPricesAndUsesRawIdLabels() {
    Id standardPricebookId = Test.getStandardPricebookId();
    Product2 product = new Product2(Name = 'Filtered Product', IsActive = true);
    insert product;
    insert new PricebookEntry(
      Pricebook2Id = standardPricebookId,
      Product2Id = product.Id,
      UnitPrice = 100,
      IsActive = true
    );
    Pricebook2 targetPricebook = new Pricebook2(
      Name = 'Brand A',
      IsActive = true
    );
    Pricebook2 excludedPricebook = new Pricebook2(
      Name = 'Brand B',
      IsActive = true
    );
    insert new List<Pricebook2>{ targetPricebook, excludedPricebook };
    insert new List<PricebookEntry>{
      new PricebookEntry(
        Pricebook2Id = targetPricebook.Id,
        Product2Id = product.Id,
        UnitPrice = 90,
        IsActive = true
      ),
      new PricebookEntry(
        Pricebook2Id = excludedPricebook.Id,
        Product2Id = product.Id,
        UnitPrice = 110,
        IsActive = true
      )
    };

    Map<Id, Map<String, Decimal>> prices = CatalogProductExportSupport.loadPricesByProduct(
      new List<Product2>{ product },
      standardPricebookId,
      new Set<Id>{ targetPricebook.Id },
      new Map<Id, String>{
        targetPricebook.Id => String.valueOf(targetPricebook.Id)
      }
    );

    System.assertEquals(1, prices.get(product.Id).size());
    System.assertEquals(
      90,
      prices.get(product.Id).get(String.valueOf(targetPricebook.Id))
    );
  }

  @IsTest
  static void explicitEmptyFilterDoesNotFallBackToAllPrices() {
    Product2 product = new Product2(Name = 'No Prices', IsActive = true);
    insert product;

    Map<Id, Map<String, Decimal>> prices = CatalogProductExportSupport.loadPricesByProduct(
      new List<Product2>{ product },
      Test.getStandardPricebookId(),
      new Set<Id>(),
      new Map<Id, String>()
    );

    System.assertEquals(true, prices.isEmpty());
  }

  @IsTest
  static void finalPriceKeyCollisionsPreserveSellingModelSuffix() {
    Id pricebookId = Id.valueOf('01s000000000001');
    Id pricebookEntryId = Id.valueOf('01u000000000001');
    Id sellingModelId = Id.valueOf('001000000000001');
    String sellingModelSuffix = ':' + String.valueOf(sellingModelId);
    Map<String, Decimal> existingPrices = new Map<String, Decimal>{
      'RETAIL' + sellingModelSuffix => 10,
      'Retail [' +
      String.valueOf(pricebookId) +
      ']' +
      sellingModelSuffix => 11,
      'Retail [' +
      String.valueOf(pricebookId) +
      ':' +
      String.valueOf(pricebookEntryId) +
      ']' +
      sellingModelSuffix => 12
    };

    String priceKey = CatalogProductExportSupport.buildUniquePriceKey(
      existingPrices,
      'Retail',
      sellingModelId,
      pricebookId,
      pricebookEntryId
    );

    System.assert(priceKey.endsWith(sellingModelSuffix));
    System.assert(
      !new Set<String>{
          'retail' + sellingModelSuffix.toLowerCase(),
          ('Retail [' +
            String.valueOf(pricebookId) +
            ']' +
            sellingModelSuffix)
            .toLowerCase(),
          ('Retail [' +
            String.valueOf(pricebookId) +
            ':' +
            String.valueOf(pricebookEntryId) +
            ']' +
            sellingModelSuffix)
            .toLowerCase()
        }
        .contains(priceKey.toLowerCase()),
      'Final key allocation must not overwrite an existing case-insensitive collision'
    );
  }
}
