// ==========================================================================
// seedBuyerGroupAvailability.apex
// Seeds minimal B2B Commerce entitlement data for scratch org testing:
// - Creates three demo WebStores (US, CA, Shared)
// - Creates three additional Pricebooks (US Retail, CA Retail, Wholesale)
// - Links pricebooks to stores via WebStorePricebook (simulating real Commerce)
// - Creates PricebookEntry records for demo products in each pricebook
// - Creates three Buyer Groups (all, limited, empty)
// - Creates matching entitlement policies
// - Links buyer groups to all stores and policies
// - Links the policies to existing demo products imported by commerce-plan.json
//
// Store → Pricebook mapping:
//   US B2B Store  → US Retail + Wholesale
//   CA B2B Store  → CA Retail + Wholesale (Wholesale is shared/deduped)
//   Demo Store    → Demo Price Book (existing)
//
// Test scenarios:
//   WebStoreIds = US only        → US Retail + Wholesale
//   WebStoreIds = US + CA        → US Retail + CA Retail + Wholesale (deduped)
//   WebStoreIds = all three      → US Retail + CA Retail + Wholesale + Demo
// ==========================================================================

System.debug('▶️ Starting Buyer Group availability seed...');

String webStoreName = 'Demo B2B Entitlement Store';
String usStoreName = 'US B2B Store';
String caStoreName = 'CA B2B Store';
String usRetailPbName = 'US Retail';
String caRetailPbName = 'CA Retail';
String wholesalePbName = 'Wholesale';
String allGroupName = 'Demo Buyer Group - All Products';
String limitedGroupName = 'Demo Buyer Group - Limited Products';
String emptyGroupName = 'Demo Buyer Group - Empty';
String allPolicyName = 'Demo Entitlement Policy - All Products';
String limitedPolicyName = 'Demo Entitlement Policy - Limited Products';
String emptyPolicyName = 'Demo Entitlement Policy - Empty';
String simpleCatalogName = 'Demo Catalog - Simple Products';
Integer limitedProductCount = 3;

List<ProductCatalog> catalogs = [
  SELECT Id, Name
  FROM ProductCatalog
  WHERE Name = :simpleCatalogName
  LIMIT 1
];

System.assert(
  !catalogs.isEmpty(),
  'The demo ProductCatalog "' +
    simpleCatalogName +
    '" was not found. Run bash scripts/orgInit.sh <alias> or bash scripts/reset-commerce-data.sh <alias> first.'
);

ProductCatalog simpleCatalog = catalogs[0];

List<ProductCategory> simpleCatalogCategories = [
  SELECT Id
  FROM ProductCategory
  WHERE CatalogId = :simpleCatalog.Id
];

System.assert(
  !simpleCatalogCategories.isEmpty(),
  'No ProductCategory records were found for the demo ProductCatalog "' +
    simpleCatalogName +
    '".'
);

Set<Id> simpleCatalogCategoryIds = new Map<Id, ProductCategory>(
    simpleCatalogCategories
  )
  .keySet();
Set<Id> simpleCatalogProductIds = new Set<Id>();

for (ProductCategoryProduct categoryProductLink : [
  SELECT ProductId
  FROM ProductCategoryProduct
  WHERE ProductCategoryId IN :simpleCatalogCategoryIds
]) {
  simpleCatalogProductIds.add(categoryProductLink.ProductId);
}

List<Product2> demoProducts = [
  SELECT Id, Name, ProductCode
  FROM Product2
  WHERE Id IN :simpleCatalogProductIds AND IsActive = TRUE
  ORDER BY ProductCode
];

System.assert(
  !demoProducts.isEmpty(),
  'No active demo products were found for the ProductCatalog "' +
    simpleCatalogName +
    '".'
);

List<Product2> limitedProducts = new List<Product2>();
for (
  Integer i = 0; i < Math.min(limitedProductCount, demoProducts.size()); i++
) {
  limitedProducts.add(demoProducts[i]);
}

SObject ensureWebStore(String name) {
  Schema.SObjectType webStoreType = Schema.getGlobalDescribe().get('WebStore');
  System.assertNotEquals(
    null,
    webStoreType,
    'WebStore is unavailable. Recreate this org from the Commerce-enabled B2B scratch definition.'
  );

  List<SObject> stores = Database.query(
    'SELECT Id, Name FROM WebStore WHERE Name = :name LIMIT 1'
  );

  if (!stores.isEmpty()) {
    return stores[0];
  }

  SObject store = webStoreType.newSObject();
  store.put('Name', name);

  Map<String, Schema.SObjectField> webStoreFields = webStoreType
    .getDescribe()
    .fields.getMap();
  for (
    String optionField : new List<String>{
      'OptionsAutoFacetingEnabled',
      'OptionsCartAsyncProcessingEnabled',
      'OptionsCartCalculateEnabled',
      'OptionsCartToOrderAutoCustomFieldMapping',
      'OptionsCommerceEinsteinActivitiesTracked',
      'OptionsCommerceEinsteinDeployed',
      'OptionsDuplicateCartItemsEnabled',
      'OptionsGuestBrowsingEnabled',
      'OptionsGuestCartEnabled',
      'OptionsGuestCheckoutEnabled',
      'OptionsPreserveGuestCartEnabled',
      'OptionsSkipAdditionalEntitlementCheckForSearch',
      'OptionsSkuDetectionEnabled',
      'OptionsSplitShipmentEnabled'
    }
  ) {
    if (
      webStoreFields.containsKey(optionField) &&
      webStoreFields.get(optionField).getDescribe().isCreateable()
    ) {
      store.put(optionField, false);
    }
  }

  insert store;
  return store;
}

SObject ensureBuyerGroup(String name) {
  List<SObject> buyerGroups = Database.query(
    'SELECT Id, Name FROM BuyerGroup WHERE Name = :name LIMIT 1'
  );

  if (!buyerGroups.isEmpty()) {
    return buyerGroups[0];
  }

  SObject buyerGroup = Schema.getGlobalDescribe()
    .get('BuyerGroup')
    .newSObject();
  buyerGroup.put('Name', name);
  insert buyerGroup;
  return buyerGroup;
}

SObject ensurePolicy(
  String name,
  Boolean canViewProduct,
  Boolean canViewPrice
) {
  List<SObject> policies = Database.query(
    'SELECT Id, Name, CanViewProduct, CanViewPrice FROM CommerceEntitlementPolicy WHERE Name = :name LIMIT 1'
  );

  if (!policies.isEmpty()) {
    SObject existing = policies[0];
    Boolean needsUpdate = false;

    if ((Boolean) existing.get('CanViewProduct') != canViewProduct) {
      existing.put('CanViewProduct', canViewProduct);
      needsUpdate = true;
    }

    if ((Boolean) existing.get('CanViewPrice') != canViewPrice) {
      existing.put('CanViewPrice', canViewPrice);
      needsUpdate = true;
    }

    if (needsUpdate) {
      update existing;
    }

    return existing;
  }

  SObject policy = Schema.getGlobalDescribe()
    .get('CommerceEntitlementPolicy')
    .newSObject();
  policy.put('Name', name);
  policy.put('CanViewProduct', canViewProduct);
  policy.put('CanViewPrice', canViewPrice);
  insert policy;
  return policy;
}

void ensureWebStoreBuyerGroup(Id webStoreId, Id buyerGroupId) {
  List<SObject> links = Database.query(
    'SELECT Id FROM WebStoreBuyerGroup WHERE WebStoreId = :webStoreId AND BuyerGroupId = :buyerGroupId LIMIT 1'
  );

  if (links.isEmpty()) {
    SObject link = Schema.getGlobalDescribe()
      .get('WebStoreBuyerGroup')
      .newSObject();
    link.put('WebStoreId', webStoreId);
    link.put('BuyerGroupId', buyerGroupId);
    insert link;
  }
}

void ensureWebStorePricebook(Id webStoreId, Id pricebookId) {
  Schema.SObjectType wspType = Schema.getGlobalDescribe()
    .get('WebStorePricebook');
  if (wspType == null) {
    return;
  }

  List<SObject> links = Database.query(
    'SELECT Id FROM WebStorePricebook WHERE WebStoreId = :webStoreId AND Pricebook2Id = :pricebookId LIMIT 1'
  );

  if (links.isEmpty()) {
    SObject link = wspType.newSObject();
    link.put('WebStoreId', webStoreId);
    link.put('Pricebook2Id', pricebookId);
    insert link;
  }
}

Pricebook2 ensurePricebook(String name) {
  List<Pricebook2> existing = [
    SELECT Id, Name
    FROM Pricebook2
    WHERE Name = :name
    LIMIT 1
  ];

  if (!existing.isEmpty()) {
    return existing[0];
  }

  Pricebook2 pb = new Pricebook2(Name = name, IsActive = true);
  insert pb;
  return pb;
}

void ensurePricebookEntries(
  Id pricebookId,
  List<Product2> products,
  Decimal unitPrice
) {
  Id standardPbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = TRUE LIMIT 1]
  .Id;

  Set<Id> productIds = new Map<Id, Product2>(products).keySet();

  // Ensure standard PBEs exist (required before custom PBEs)
  Set<Id> productIdsWithStdEntry = new Set<Id>();
  for (PricebookEntry pbe : [
    SELECT Product2Id
    FROM PricebookEntry
    WHERE Pricebook2Id = :standardPbId AND Product2Id IN :productIds
  ]) {
    productIdsWithStdEntry.add(pbe.Product2Id);
  }
  List<PricebookEntry> stdEntries = new List<PricebookEntry>();
  for (Product2 p : products) {
    if (!productIdsWithStdEntry.contains(p.Id)) {
      stdEntries.add(
        new PricebookEntry(
          Pricebook2Id = standardPbId,
          Product2Id = p.Id,
          UnitPrice = 100,
          IsActive = true
        )
      );
    }
  }
  if (!stdEntries.isEmpty()) {
    insert stdEntries;
  }

  // Ensure custom PBEs
  Set<Id> productIdsWithEntry = new Set<Id>();
  for (PricebookEntry pbe : [
    SELECT Product2Id
    FROM PricebookEntry
    WHERE Pricebook2Id = :pricebookId AND Product2Id IN :productIds
  ]) {
    productIdsWithEntry.add(pbe.Product2Id);
  }
  List<PricebookEntry> newEntries = new List<PricebookEntry>();
  for (Product2 p : products) {
    if (!productIdsWithEntry.contains(p.Id)) {
      newEntries.add(
        new PricebookEntry(
          Pricebook2Id = pricebookId,
          Product2Id = p.Id,
          UnitPrice = unitPrice,
          IsActive = true
        )
      );
    }
  }
  if (!newEntries.isEmpty()) {
    insert newEntries;
  }
}

void ensurePolicyBuyerGroup(Id policyId, Id buyerGroupId) {
  List<SObject> links = Database.query(
    'SELECT Id FROM CommerceEntitlementBuyerGroup WHERE PolicyId = :policyId AND BuyerGroupId = :buyerGroupId LIMIT 1'
  );

  if (links.isEmpty()) {
    SObject link = Schema.getGlobalDescribe()
      .get('CommerceEntitlementBuyerGroup')
      .newSObject();
    link.put('PolicyId', policyId);
    link.put('BuyerGroupId', buyerGroupId);
    insert link;
  }
}

void syncPolicyProducts(Id policyId, Set<Id> desiredProductIds) {
  List<SObject> existingLinks = Database.query(
    'SELECT Id, ProductId FROM CommerceEntitlementProduct WHERE PolicyId = :policyId'
  );
  Map<Id, SObject> existingLinksByProductId = new Map<Id, SObject>();

  for (SObject existingLink : existingLinks) {
    existingLinksByProductId.put(
      (Id) existingLink.get('ProductId'),
      existingLink
    );
  }

  List<SObject> linksToInsert = new List<SObject>();
  for (Id desiredProductId : desiredProductIds) {
    if (!existingLinksByProductId.containsKey(desiredProductId)) {
      SObject link = Schema.getGlobalDescribe()
        .get('CommerceEntitlementProduct')
        .newSObject();
      link.put('PolicyId', policyId);
      link.put('ProductId', desiredProductId);
      linksToInsert.add(link);
    }
  }

  List<SObject> linksToDelete = new List<SObject>();
  for (Id existingProductId : existingLinksByProductId.keySet()) {
    if (!desiredProductIds.contains(existingProductId)) {
      linksToDelete.add(existingLinksByProductId.get(existingProductId));
    }
  }

  if (!linksToInsert.isEmpty()) {
    insert linksToInsert;
  }

  if (!linksToDelete.isEmpty()) {
    delete linksToDelete;
  }
}

SObject webStore = ensureWebStore(webStoreName);
Id webStoreId = (Id) webStore.get('Id');
SObject usStore = ensureWebStore(usStoreName);
Id usStoreId = (Id) usStore.get('Id');
SObject caStore = ensureWebStore(caStoreName);
Id caStoreId = (Id) caStore.get('Id');

// Create pricebooks
Pricebook2 usRetailPb = ensurePricebook(usRetailPbName);
Pricebook2 caRetailPb = ensurePricebook(caRetailPbName);
Pricebook2 wholesalePb = ensurePricebook(wholesalePbName);

// Existing Demo Price Book
Pricebook2 demoPb = [
  SELECT Id, Name
  FROM Pricebook2
  WHERE Name = 'Demo Price Book' AND IsActive = TRUE
  LIMIT 1
];

// Link pricebooks to stores (simulates Commerce store configuration)
// US Store -> US Retail + Wholesale
ensureWebStorePricebook(usStoreId, usRetailPb.Id);
ensureWebStorePricebook(usStoreId, wholesalePb.Id);
// CA Store -> CA Retail + Wholesale (shared)
ensureWebStorePricebook(caStoreId, caRetailPb.Id);
ensureWebStorePricebook(caStoreId, wholesalePb.Id);
// Demo Store -> Demo Price Book
ensureWebStorePricebook(webStoreId, demoPb.Id);

// Create PricebookEntry records for demo products
ensurePricebookEntries(usRetailPb.Id, demoProducts, 99.99);
ensurePricebookEntries(caRetailPb.Id, demoProducts, 129.99);
ensurePricebookEntries(wholesalePb.Id, demoProducts, 74.99);

SObject allBuyerGroup = ensureBuyerGroup(allGroupName);
SObject limitedBuyerGroup = ensureBuyerGroup(limitedGroupName);
SObject emptyBuyerGroup = ensureBuyerGroup(emptyGroupName);

SObject allPolicy = ensurePolicy(allPolicyName, true, true);
SObject limitedPolicy = ensurePolicy(limitedPolicyName, true, true);
SObject emptyPolicy = ensurePolicy(emptyPolicyName, true, false);

// Link buyer groups to ALL stores
ensureWebStoreBuyerGroup(webStoreId, (Id) allBuyerGroup.get('Id'));
ensureWebStoreBuyerGroup(webStoreId, (Id) limitedBuyerGroup.get('Id'));
ensureWebStoreBuyerGroup(webStoreId, (Id) emptyBuyerGroup.get('Id'));
ensureWebStoreBuyerGroup(usStoreId, (Id) allBuyerGroup.get('Id'));
ensureWebStoreBuyerGroup(usStoreId, (Id) limitedBuyerGroup.get('Id'));
ensureWebStoreBuyerGroup(caStoreId, (Id) allBuyerGroup.get('Id'));
ensureWebStoreBuyerGroup(caStoreId, (Id) limitedBuyerGroup.get('Id'));

ensurePolicyBuyerGroup((Id) allPolicy.get('Id'), (Id) allBuyerGroup.get('Id'));
ensurePolicyBuyerGroup(
  (Id) limitedPolicy.get('Id'),
  (Id) limitedBuyerGroup.get('Id')
);
ensurePolicyBuyerGroup(
  (Id) emptyPolicy.get('Id'),
  (Id) emptyBuyerGroup.get('Id')
);

Set<Id> allProductIds = new Map<Id, Product2>(demoProducts).keySet();
Set<Id> limitedProductIds = new Map<Id, Product2>(limitedProducts).keySet();

syncPolicyProducts((Id) allPolicy.get('Id'), allProductIds);
syncPolicyProducts((Id) limitedPolicy.get('Id'), limitedProductIds);
syncPolicyProducts((Id) emptyPolicy.get('Id'), new Set<Id>());

List<String> allProductCodes = new List<String>();
for (Product2 product : demoProducts) {
  allProductCodes.add(product.ProductCode);
}

List<String> limitedProductCodes = new List<String>();
for (Product2 product : limitedProducts) {
  limitedProductCodes.add(product.ProductCode);
}

Map<String, Object> summary = new Map<String, Object>{
  'catalogName' => simpleCatalog.Name,
  'catalogId' => simpleCatalog.Id,
  'webStores' => new List<Object>{
    new Map<String, Object>{
      'name' => (String) webStore.get('Name'),
      'id' => webStoreId,
      'pricebooks' => new List<String>{ demoPb.Name }
    },
    new Map<String, Object>{
      'name' => (String) usStore.get('Name'),
      'id' => usStoreId,
      'pricebooks' => new List<String>{ usRetailPb.Name, wholesalePb.Name }
    },
    new Map<String, Object>{
      'name' => (String) caStore.get('Name'),
      'id' => caStoreId,
      'pricebooks' => new List<String>{ caRetailPb.Name, wholesalePb.Name }
    }
  },
  'buyerGroups' => new List<Object>{
    new Map<String, Object>{
      'name' => (String) allBuyerGroup.get('Name'),
      'id' => (Id) allBuyerGroup.get('Id'),
      'productCodes' => allProductCodes
    },
    new Map<String, Object>{
      'name' => (String) limitedBuyerGroup.get('Name'),
      'id' => (Id) limitedBuyerGroup.get('Id'),
      'productCodes' => limitedProductCodes
    },
    new Map<String, Object>{
      'name' => (String) emptyBuyerGroup.get('Name'),
      'id' => (Id) emptyBuyerGroup.get('Id'),
      'productCodes' => new List<String>()
    }
  }
};

System.debug('RESULT_JSON ' + JSON.serializePretty(summary));
System.debug(
  'NEXT_STEP Set CatalogJobConfig__mdt.WebStoreIds__c to one or more store IDs: ' +
    webStoreId +
    ', ' +
    usStoreId +
    ', ' +
    caStoreId +
    '. Set EnableBuyerGroupAvailability__c = true and provide your AvailabilitySourceId__c before running BuyerGroupAvailabilityExportBatch.'
);
System.debug('Test scenarios:');
System.debug('  WebStoreIds = ' + usStoreId + ' -> US Retail + Wholesale');
System.debug(
  '  WebStoreIds = ' +
    usStoreId +
    ',' +
    caStoreId +
    ' -> US Retail + CA Retail + Wholesale (deduped)'
);
System.debug(
  '  WebStoreIds = ' +
    usStoreId +
    ',' +
    caStoreId +
    ',' +
    webStoreId +
    ' -> US Retail + CA Retail + Wholesale + Demo'
);
System.debug('🎉 Buyer Group availability seed complete!');
