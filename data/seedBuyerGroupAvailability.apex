// ==========================================================================
// seedBuyerGroupAvailability.apex
// Seeds minimal B2B Commerce entitlement data for scratch org testing:
// - Creates one demo WebStore
// - Creates three Buyer Groups (all, limited, empty)
// - Creates matching entitlement policies
// - Links buyer groups to the store and policies
// - Links the policies to existing demo products imported by commerce-plan.json
// ==========================================================================

System.debug('▶️ Starting Buyer Group availability seed...');

String webStoreName = 'Demo B2B Entitlement Store';
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

for (
  ProductCategoryProduct categoryProductLink : [
    SELECT ProductId
    FROM ProductCategoryProduct
    WHERE ProductCategoryId IN :simpleCatalogCategoryIds
  ]
) {
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
for (Integer i = 0; i < Math.min(limitedProductCount, demoProducts.size()); i++) {
  limitedProducts.add(demoProducts[i]);
}

WebStore ensureWebStore(String name) {
  List<WebStore> stores = [
    SELECT Id, Name
    FROM WebStore
    WHERE Name = :name
    LIMIT 1
  ];

  if (!stores.isEmpty()) {
    return stores[0];
  }

  WebStore store = new WebStore(
    Name = name,
    OptionsAutoFacetingEnabled = false,
    OptionsCartAsyncProcessingEnabled = false,
    OptionsCartCalculateEnabled = false,
    OptionsCartToOrderAutoCustomFieldMapping = false,
    OptionsCommerceEinsteinActivitiesTracked = false,
    OptionsCommerceEinsteinDeployed = false,
    OptionsDuplicateCartItemsEnabled = false,
    OptionsGuestBrowsingEnabled = false,
    OptionsGuestCartEnabled = false,
    OptionsGuestCheckoutEnabled = false,
    OptionsPreserveGuestCartEnabled = false,
    OptionsSkipAdditionalEntitlementCheckForSearch = false,
    OptionsSkuDetectionEnabled = false,
    OptionsSplitShipmentEnabled = false
  );
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
    existingLinksByProductId.put((Id) existingLink.get('ProductId'), existingLink);
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

WebStore webStore = ensureWebStore(webStoreName);
SObject allBuyerGroup = ensureBuyerGroup(allGroupName);
SObject limitedBuyerGroup = ensureBuyerGroup(limitedGroupName);
SObject emptyBuyerGroup = ensureBuyerGroup(emptyGroupName);

SObject allPolicy = ensurePolicy(allPolicyName, true, true);
SObject limitedPolicy = ensurePolicy(limitedPolicyName, true, true);
SObject emptyPolicy = ensurePolicy(emptyPolicyName, true, false);

ensureWebStoreBuyerGroup(webStore.Id, (Id) allBuyerGroup.get('Id'));
ensureWebStoreBuyerGroup(webStore.Id, (Id) limitedBuyerGroup.get('Id'));
ensureWebStoreBuyerGroup(webStore.Id, (Id) emptyBuyerGroup.get('Id'));

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
  'webStoreName' => webStore.Name,
  'webStoreId' => webStore.Id,
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
  'NEXT_STEP Set CatalogJobConfig__mdt.WebStoreId__c = ' +
    webStore.Id +
    ', set EnableBuyerGroupAvailability__c = true, and provide your AvailabilitySourceId__c before running BuyerGroupAvailabilityExportBatch.'
);
System.debug('🎉 Buyer Group availability seed complete!');
