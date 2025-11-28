// ==========================================================================
// seedPrices.apex
// Seeds pricing for demo product data:
// - Ensures Standard Price Book is active
// - Creates Standard PricebookEntries for all demo products
// - Creates matching Demo Price Book entries (defined in your JSON plan)
// ==========================================================================

System.debug('▶️ Starting pricebook seeding...');

// ------------------------------------------------------------
// 1) Load all demo products
// ------------------------------------------------------------
List<Product2> products = [
  SELECT Id, Name, ProductCode
  FROM Product2
  WHERE ProductCode LIKE 'SKU-%'
];

System.debug('Found demo products: ' + products.size());

// ------------------------------------------------------------
// 2) Get Standard Price Book
// ------------------------------------------------------------
Pricebook2 standardPb = [
  SELECT Id, IsActive
  FROM Pricebook2
  WHERE IsStandard = TRUE
  LIMIT 1
];

if (!standardPb.IsActive) {
  standardPb.IsActive = true;
  update standardPb;
  System.debug('Activated Standard Price Book');
}

// ------------------------------------------------------------
// 3) Get Demo Price Book
// ------------------------------------------------------------
Pricebook2 demoPb;

List<Pricebook2> demoPbs = [
  SELECT Id, Name, IsActive
  FROM Pricebook2
  WHERE Name = 'Demo Price Book'
  LIMIT 1
];

if (!demoPbs.isEmpty()) {
  demoPb = demoPbs[0];
  if (!demoPb.IsActive) {
    demoPb.IsActive = true;
    update demoPb;
    System.debug('Activated Demo Price Book');
  }
} else {
  System.debug('⚠️ No Demo Price Book found. Skipping custom price entries.');
}

// ------------------------------------------------------------
// 4) Generate price value based on ProductCode prefix
// ------------------------------------------------------------
Decimal getPrice(Product2 p) {
  if (p.ProductCode.startsWith('SKU-DRL'))
    return 129.99; // drills
  if (p.ProductCode.startsWith('SKU-SAW'))
    return 159.99; // saws
  if (p.ProductCode.startsWith('SKU-SND'))
    return 99.99; // sander
  if (p.ProductCode.startsWith('SKU-WRH'))
    return 49.99; // wrench
  if (p.ProductCode.startsWith('SKU-SCR'))
    return 39.99; // screwdriver
  if (p.ProductCode.startsWith('SKU-HAM'))
    return 29.99; // hammer
  if (p.ProductCode.startsWith('SKU-CHN'))
    return 249.99; // chainsaw

  return 99.00; // fallback price
}

// ------------------------------------------------------------
// 5) Seed Standard Price Book entries for all demo products
// ------------------------------------------------------------
List<PricebookEntry> standardEntries = new List<PricebookEntry>();

// Prevent duplicates: query existing entries first
Set<Id> alreadyPricedStandard = new Set<Id>();

for (PricebookEntry pbe : [
  SELECT Product2Id
  FROM PricebookEntry
  WHERE Pricebook2Id = :standardPb.Id
]) {
  alreadyPricedStandard.add(pbe.Product2Id);
}

for (Product2 p : products) {
  if (!alreadyPricedStandard.contains(p.Id)) {
    standardEntries.add(
      new PricebookEntry(
        Pricebook2Id = standardPb.Id,
        Product2Id = p.Id,
        UnitPrice = getPrice(p),
        IsActive = true,
        UseStandardPrice = false
      )
    );
  }
}

if (!standardEntries.isEmpty()) {
  insert standardEntries;
  System.debug('✅ Inserted Standard PBEs: ' + standardEntries.size());
} else {
  System.debug('ℹ️ No new Standard PBEs to insert.');
}

// ------------------------------------------------------------
// 6) Seed Demo Price Book entries (optional)
// ------------------------------------------------------------
if (demoPb != null) {
  List<PricebookEntry> demoEntries = new List<PricebookEntry>();
  Set<Id> alreadyPricedDemo = new Set<Id>();

  // Find existing demo entries to avoid duplicates
  for (PricebookEntry pbe : [
    SELECT Product2Id
    FROM PricebookEntry
    WHERE Pricebook2Id = :demoPb.Id
  ]) {
    alreadyPricedDemo.add(pbe.Product2Id);
  }

  for (Product2 p : products) {
    if (!alreadyPricedDemo.contains(p.Id)) {
      demoEntries.add(
        new PricebookEntry(
          Pricebook2Id = demoPb.Id,
          Product2Id = p.Id,
          UnitPrice = getPrice(p),
          IsActive = true,
          UseStandardPrice = false
        )
      );
    }
  }

  if (!demoEntries.isEmpty()) {
    insert demoEntries;
    System.debug('✅ Inserted Demo PBEs: ' + demoEntries.size());
  } else {
    System.debug('ℹ️ No new Demo PBEs to insert.');
  }
}

System.debug('🎉 Price seeding complete!');
