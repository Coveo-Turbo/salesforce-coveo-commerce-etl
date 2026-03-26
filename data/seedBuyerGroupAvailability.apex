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

CommerceEntitlementPolicy ensurePolicy(
  String name,
  Boolean canViewProduct,
  Boolean canViewPrice
) {
  List<CommerceEntitlementPolicy> policies = [
    SELECT Id, Name, CanViewProduct, CanViewPrice
    FROM CommerceEntitlementPolicy
    WHERE Name = :name
    LIMIT 1
  ];

  if (!policies.isEmpty()) {
    CommerceEntitlementPolicy existing = policies[0];
    Boolean needsUpdate = false;

    if (existing.CanViewProduct != canViewProduct) {
      existing.CanViewProduct = canViewProduct;
      needsUpdate = true;
    }

    if (existing.CanViewPrice != canViewPrice) {
      existing.CanViewPrice = canViewPrice;
      needsUpdate = true;
    }

    if (needsUpdate) {
      update existing;
    }

    return existing;
  }

  CommerceEntitlementPolicy policy = new CommerceEntitlementPolicy(
    Name = name,
    CanViewProduct = canViewProduct,
    CanViewPrice = canViewPrice
  );
  insert policy;
  return policy;
}

void ensureWebStoreBuyerGroup(Id webStoreId, Id buyerGroupId) {
  List<WebStoreBuyerGroup> links = [
    SELECT Id
    FROM WebStoreBuyerGroup
    WHERE WebStoreId = :webStoreId AND BuyerGroupId = :buyerGroupId
    LIMIT 1
  ];

  if (links.isEmpty()) {
    insert new WebStoreBuyerGroup(
      WebStoreId = webStoreId,
      BuyerGroupId = buyerGroupId
    );
  }
}

void ensurePolicyBuyerGroup(Id policyId, Id buyerGroupId) {
  List<CommerceEntitlementBuyerGroup> links = [
    SELECT Id
    FROM CommerceEntitlementBuyerGroup
    WHERE PolicyId = :policyId AND BuyerGroupId = :buyerGroupId
    LIMIT 1
  ];

  if (links.isEmpty()) {
    insert new CommerceEntitlementBuyerGroup(
      PolicyId = policyId,
      BuyerGroupId = buyerGroupId
    );
  }
}

void ensurePolicyProduct(Id policyId, Id productId) {
  List<CommerceEntitlementProduct> links = [
    SELECT Id
    FROM CommerceEntitlementProduct
    WHERE PolicyId = :policyId AND ProductId = :productId
    LIMIT 1
  ];

  if (links.isEmpty()) {
    insert new CommerceEntitlementProduct(
      PolicyId = policyId,
      ProductId = productId
    );
  }
}

WebStore webStore = ensureWebStore(webStoreName);
SObject allBuyerGroup = ensureBuyerGroup(allGroupName);
SObject limitedBuyerGroup = ensureBuyerGroup(limitedGroupName);
SObject emptyBuyerGroup = ensureBuyerGroup(emptyGroupName);

CommerceEntitlementPolicy allPolicy = ensurePolicy(allPolicyName, true, true);
CommerceEntitlementPolicy limitedPolicy = ensurePolicy(
  limitedPolicyName,
  true,
  true
);
CommerceEntitlementPolicy emptyPolicy = ensurePolicy(
  emptyPolicyName,
  true,
  false
);

ensureWebStoreBuyerGroup(webStore.Id, (Id) allBuyerGroup.get('Id'));
ensureWebStoreBuyerGroup(webStore.Id, (Id) limitedBuyerGroup.get('Id'));
ensureWebStoreBuyerGroup(webStore.Id, (Id) emptyBuyerGroup.get('Id'));

ensurePolicyBuyerGroup(allPolicy.Id, (Id) allBuyerGroup.get('Id'));
ensurePolicyBuyerGroup(limitedPolicy.Id, (Id) limitedBuyerGroup.get('Id'));
ensurePolicyBuyerGroup(emptyPolicy.Id, (Id) emptyBuyerGroup.get('Id'));

ensurePolicyProduct(allPolicy.Id, primaryProduct.Id);
ensurePolicyProduct(allPolicy.Id, secondaryProduct.Id);
ensurePolicyProduct(limitedPolicy.Id, primaryProduct.Id);

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
