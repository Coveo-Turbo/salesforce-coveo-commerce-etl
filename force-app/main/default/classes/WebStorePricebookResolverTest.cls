@IsTest
private class WebStorePricebookResolverTest {
  private static Boolean hasBuyerGroupPricebookSchema() {
    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    return globalDescribe.containsKey('WebStore') &&
      globalDescribe.containsKey('BuyerGroup') &&
      globalDescribe.containsKey('WebStorePricebook') &&
      globalDescribe.containsKey('WebStoreBuyerGroup') &&
      globalDescribe.containsKey('BuyerGroupPricebook');
  }

  private static SObject createWebStore(String name) {
    SObject store = Schema.getGlobalDescribe().get('WebStore').newSObject();
    store.put('Name', name);
    store.put('OptionsAutoFacetingEnabled', false);
    store.put('OptionsCartAsyncProcessingEnabled', false);
    store.put('OptionsCartCalculateEnabled', false);
    store.put('OptionsCartToOrderAutoCustomFieldMapping', false);
    store.put('OptionsCommerceEinsteinActivitiesTracked', false);
    store.put('OptionsCommerceEinsteinDeployed', false);
    store.put('OptionsDuplicateCartItemsEnabled', false);
    store.put('OptionsGuestBrowsingEnabled', false);
    store.put('OptionsGuestCartEnabled', false);
    store.put('OptionsGuestCheckoutEnabled', false);
    store.put('OptionsPreserveGuestCartEnabled', false);
    store.put('OptionsSkipAdditionalEntitlementCheckForSearch', false);
    store.put('OptionsSkuDetectionEnabled', false);
    store.put('OptionsSplitShipmentEnabled', false);
    insert store;
    return store;
  }

  private static SObject createBuyerGroup(String name) {
    SObject buyerGroup = Schema.getGlobalDescribe()
      .get('BuyerGroup')
      .newSObject();
    buyerGroup.put('Name', name);
    insert buyerGroup;
    return buyerGroup;
  }

  private static void linkWebStorePricebook(
    Id webStoreId,
    Id pricebookId,
    Boolean isActive
  ) {
    SObject link = Schema.getGlobalDescribe()
      .get('WebStorePricebook')
      .newSObject();
    link.put('WebStoreId', webStoreId);
    link.put('Pricebook2Id', pricebookId);
    link.put('IsActive', isActive);
    insert link;
  }

  private static void linkWebStoreBuyerGroup(
    Id webStoreId,
    Id buyerGroupId
  ) {
    SObject link = Schema.getGlobalDescribe()
      .get('WebStoreBuyerGroup')
      .newSObject();
    link.put('WebStoreId', webStoreId);
    link.put('BuyerGroupId', buyerGroupId);
    insert link;
  }

  private static void linkBuyerGroupPricebook(
    Id buyerGroupId,
    Id pricebookId,
    Boolean isActive
  ) {
    SObject link = Schema.getGlobalDescribe()
      .get('BuyerGroupPricebook')
      .newSObject();
    link.put('BuyerGroupId', buyerGroupId);
    link.put('Pricebook2Id', pricebookId);
    link.put('IsActive', isActive);
    insert link;
  }

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
  static void resolvesActiveDirectAndBuyerGroupPricebooks() {
    if (!hasBuyerGroupPricebookSchema()) {
      return;
    }

    SObject store = createWebStore('Resolver Store');
    SObject secondStore = createWebStore('Resolver Store Two');
    SObject buyerGroup = createBuyerGroup('Resolver Buyer Group');
    SObject excludedStrikethroughGroup = createBuyerGroup(
      'Excluded Strikethrough Group'
    );
    Pricebook2 activeDirectPricebook = new Pricebook2(
      Name = 'Active Direct',
      IsActive = true
    );
    Pricebook2 inactiveDirectPricebook = new Pricebook2(
      Name = 'Inactive Direct',
      IsActive = true
    );
    Pricebook2 activeBuyerGroupPricebook = new Pricebook2(
      Name = 'Active Buyer Group',
      IsActive = true
    );
    Pricebook2 inactiveBuyerGroupPricebook = new Pricebook2(
      Name = 'Inactive Buyer Group',
      IsActive = true
    );
    Pricebook2 excludedStrikethroughPricebook = new Pricebook2(
      Name = 'Excluded Strikethrough',
      IsActive = true
    );
    insert new List<Pricebook2>{
      activeDirectPricebook,
      inactiveDirectPricebook,
      activeBuyerGroupPricebook,
      inactiveBuyerGroupPricebook,
      excludedStrikethroughPricebook
    };

    linkWebStorePricebook(
      (Id) store.get('Id'),
      activeDirectPricebook.Id,
      true
    );
    linkWebStorePricebook(
      (Id) store.get('Id'),
      inactiveDirectPricebook.Id,
      false
    );
    linkWebStoreBuyerGroup(
      (Id) store.get('Id'),
      (Id) buyerGroup.get('Id')
    );
    linkWebStoreBuyerGroup(
      (Id) secondStore.get('Id'),
      (Id) buyerGroup.get('Id')
    );
    linkWebStoreBuyerGroup(
      (Id) store.get('Id'),
      (Id) excludedStrikethroughGroup.get('Id')
    );
    linkBuyerGroupPricebook(
      (Id) buyerGroup.get('Id'),
      activeBuyerGroupPricebook.Id,
      true
    );
    linkBuyerGroupPricebook(
      (Id) buyerGroup.get('Id'),
      inactiveBuyerGroupPricebook.Id,
      false
    );
    // The same active direct Pricebook is also the shared Buyer's
    // strikethrough Pricebook. The direct store link must remain authoritative.
    linkBuyerGroupPricebook(
      (Id) buyerGroup.get('Id'),
      activeDirectPricebook.Id,
      true
    );
    linkBuyerGroupPricebook(
      (Id) excludedStrikethroughGroup.get('Id'),
      excludedStrikethroughPricebook.Id,
      true
    );
    WebStorePricebookResolver.testStrikethroughPricebookIdByBuyerGroupId = new Map<Id, Id>{
      (Id) buyerGroup.get('Id') => activeDirectPricebook.Id,
      (Id) excludedStrikethroughGroup.get('Id') => excludedStrikethroughPricebook.Id
    };

    WebStorePricebookResolver.PricebookResolution resolution = WebStorePricebookResolver.resolve(
      new CatalogJobConfig__mdt(
        WebStoreIds__c = String.valueOf(store.get('Id')) +
          ',' +
          String.valueOf(secondStore.get('Id'))
      )
    );

    System.assertEquals(
      new Set<Id>{ activeDirectPricebook.Id, activeBuyerGroupPricebook.Id },
      resolution.pricebookIds,
      'The Web Store scope should deduplicate active direct and shared Buyer Group pricebooks.'
    );
    System.assertEquals(
      false,
      resolution.pricebookIds.contains(inactiveDirectPricebook.Id)
    );
    System.assertEquals(
      false,
      resolution.pricebookIds.contains(inactiveBuyerGroupPricebook.Id)
    );
    System.assertEquals(
      false,
      resolution.pricebookIds.contains(excludedStrikethroughPricebook.Id),
      'A Buyer Group strikethrough Pricebook must be excluded when it has no active direct store link.'
    );
    System.assertEquals(
      true,
      resolution.pricebookIds.contains(activeDirectPricebook.Id),
      'An active direct link must remain authoritative even when another path identifies the Pricebook as strikethrough.'
    );
  }

  @IsTest
  static void excludesBuyerGroupStrikethroughPricebook() {
    Id buyerGroupId = Id.valueOf('0ZI000000000001');
    Id regularPricebookId = Id.valueOf('01s000000000001');
    Id strikethroughPricebookId = Id.valueOf('01s000000000002');
    Map<Id, Id> strikethroughByBuyerGroupId = new Map<Id, Id>{
      buyerGroupId => strikethroughPricebookId
    };

    System.assertEquals(
      false,
      WebStorePricebookResolver.isStrikethroughPricebook(
        buyerGroupId,
        regularPricebookId,
        strikethroughByBuyerGroupId
      )
    );
    System.assertEquals(
      true,
      WebStorePricebookResolver.isStrikethroughPricebook(
        buyerGroupId,
        strikethroughPricebookId,
        strikethroughByBuyerGroupId
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
        standardPricebookId => String.valueOf(standardPricebookId),
        targetPricebook.Id => String.valueOf(targetPricebook.Id)
      }
    );

    System.assertEquals(2, prices.get(product.Id).size());
    System.assertEquals(
      100,
      prices.get(product.Id).get(''),
      'Standard Price Book must always use the empty fallback key, even if a label is supplied.'
    );
    System.assertEquals(
      90,
      prices.get(product.Id).get(String.valueOf(targetPricebook.Id))
    );
    System.assertEquals(
      false,
      prices.get(product.Id).containsKey(String.valueOf(excludedPricebook.Id))
    );
  }

  @IsTest
  static void emptyConfiguredScopeStillIncludesOnlyStandardPricebook() {
    Id standardPricebookId = Test.getStandardPricebookId();
    Product2 product = new Product2(Name = 'No Prices', IsActive = true);
    insert product;
    insert new PricebookEntry(
      Pricebook2Id = standardPricebookId,
      Product2Id = product.Id,
      UnitPrice = 100,
      IsActive = true
    );
    Pricebook2 excludedPricebook = new Pricebook2(
      Name = 'Excluded Custom Pricebook',
      IsActive = true
    );
    insert excludedPricebook;
    insert new PricebookEntry(
      Pricebook2Id = excludedPricebook.Id,
      Product2Id = product.Id,
      UnitPrice = 125,
      IsActive = true
    );

    Map<Id, Map<String, Decimal>> prices = CatalogProductExportSupport.loadPricesByProduct(
      new List<Product2>{ product },
      standardPricebookId,
      new Set<Id>(),
      new Map<Id, String>()
    );

    System.assertEquals(1, prices.get(product.Id).size());
    System.assertEquals(100, prices.get(product.Id).get(''));
    System.assertEquals(
      false,
      prices.get(product.Id).containsKey(String.valueOf(excludedPricebook.Id)),
      'An empty configured scope must not fall back to every custom Pricebook.'
    );
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

  @IsTest
  static void standardPricebookWithSellingModelUsesFullPricebookId() {
    Id stdPricebookId = Test.getStandardPricebookId();
    Id sellingModelId = Id.valueOf('0jP000000000001');
    Id pricebookEntryId = Id.valueOf('01u000000000001');

    // When the Standard PB entry has a selling model, the basePriceKey passed to
    // buildUniquePriceKey should be the full Standard PB ID so the resulting key
    // is "01s...:0jP..." rather than the ambiguous ":0jP...".
    String priceKey = CatalogProductExportSupport.buildUniquePriceKey(
      new Map<String, Decimal>(),
      String.valueOf(stdPricebookId),
      sellingModelId,
      stdPricebookId,
      pricebookEntryId
    );

    System.assertEquals(
      String.valueOf(stdPricebookId) + ':' + String.valueOf(sellingModelId),
      priceKey,
      'Standard Price Book entries with a selling model must use the PB ID prefix'
    );
  }

  @IsTest
  static void standardPricebookWithoutSellingModelUsesEmptyKey() {
    Id stdPricebookId = Test.getStandardPricebookId();
    Id pricebookEntryId = Id.valueOf('01u000000000001');

    // When the Standard PB entry has NO selling model, the basePriceKey should be
    // empty so the resulting key is "".
    String priceKey = CatalogProductExportSupport.buildUniquePriceKey(
      new Map<String, Decimal>(),
      '',
      null,
      stdPricebookId,
      pricebookEntryId
    );

    System.assertEquals(
      '',
      priceKey,
      'Standard Price Book base entry (no selling model) must use the empty key'
    );
  }
}
