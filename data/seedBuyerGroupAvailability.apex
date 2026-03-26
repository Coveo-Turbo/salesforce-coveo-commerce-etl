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

List<Product2> demoProducts = [
  SELECT Id, Name, ProductCode
  FROM Product2
  WHERE ProductCode IN ('SKU-DRL-001', 'SKU-DRL-002', 'SKU-SAW-001')
  ORDER BY ProductCode
];

if (demoProducts.size() < 2) {
  demoProducts = [
    SELECT Id, Name, ProductCode
    FROM Product2
    WHERE IsActive = TRUE AND ProductCode LIKE 'SKU-%'
    ORDER BY ProductCode
    LIMIT 3
  ];
}

System.assert(
  demoProducts.size() >= 2,
  'At least two active demo products are required. Run bash scripts/orgInit.sh <alias> or bash scripts/reset-commerce-data.sh <alias> first.'
);

Product2 primaryProduct = demoProducts[0];
Product2 secondaryProduct = demoProducts[1];

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

void ensurePolicyProduct(Id policyId, Id productId) {
  List<SObject> links = Database.query(
    'SELECT Id FROM CommerceEntitlementProduct WHERE PolicyId = :policyId AND ProductId = :productId LIMIT 1'
  );

  if (links.isEmpty()) {
    SObject link = Schema.getGlobalDescribe()
      .get('CommerceEntitlementProduct')
      .newSObject();
    link.put('PolicyId', policyId);
    link.put('ProductId', productId);
    insert link;
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

ensurePolicyProduct((Id) allPolicy.get('Id'), primaryProduct.Id);
ensurePolicyProduct((Id) allPolicy.get('Id'), secondaryProduct.Id);
ensurePolicyProduct((Id) limitedPolicy.get('Id'), primaryProduct.Id);

Map<String, Object> summary = new Map<String, Object>{
  'webStoreName' => webStore.Name,
  'webStoreId' => webStore.Id,
  'buyerGroups' => new List<Object>{
    new Map<String, Object>{
      'name' => (String) allBuyerGroup.get('Name'),
      'id' => (Id) allBuyerGroup.get('Id'),
      'productCodes' => new List<String>{
        primaryProduct.ProductCode,
        secondaryProduct.ProductCode
      }
    },
    new Map<String, Object>{
      'name' => (String) limitedBuyerGroup.get('Name'),
      'id' => (Id) limitedBuyerGroup.get('Id'),
      'productCodes' => new List<String>{ primaryProduct.ProductCode }
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
