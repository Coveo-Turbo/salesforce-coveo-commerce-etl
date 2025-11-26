public with sharing class CatalogJsonBuilderCommerce implements ICatalogJsonBuilder {
  public String buildFullUpdateNdjson(
    List<Product2> products,
    Map<Id, PricebookEntry> pbesByProduct
  ) {
    if (products.isEmpty()) {
      return JSON.serialize(
        new Map<String, Object>{ 'addOrUpdate' => new List<Object>() }
      );
    }

    // Gather product ids
    Set<Id> pids = new Set<Id>();
    for (Product2 p : products) {
      pids.add(p.Id);
    }

    // Junctions Product2 -> ProductCategory
    List<ProductCategoryProduct> links = [
      SELECT ProductId, ProductCategoryId
      FROM ProductCategoryProduct
      WHERE ProductId IN :pids
    ];

    Set<Id> catIds = new Set<Id>();
    for (ProductCategoryProduct l : links) {
      catIds.add(l.ProductCategoryId);
    }

    // Load categories (name + parent chain)
    Map<Id, ProductCategory> catById = new Map<Id, ProductCategory>(
      [
        SELECT Id, Name, ParentCategoryId
        FROM ProductCategory
        WHERE Id IN :catIds
      ]
    );

    List<Object> addOrUpdate = new List<Object>();

    for (Product2 p : products) {
      // ---- Determine objecttype ----
      String objectType = 'Product'; // default

      // ---- Compute ec_product_id ----
      String productIdForEc = String.isNotBlank(p.ProductCode)
        ? p.ProductCode
        : (String) p.Id;

      // ---- Compute documentId ----
      String docId = objectType.toLowerCase() + '://' + productIdForEc;

      // ---- ec_name ----
      String ecName = p.Name;

      // ---- ec_category as array of strings ----
      List<String> ecCategories = buildCategoryPathsForProduct(
        p.Id,
        links,
        catById
      );
      if (ecCategories.isEmpty()) {
        if (!String.isBlank(p.Family)) {
          ecCategories.add(p.Family);
        } else {
          ecCategories.add('Uncategorized');
        }
      }

      // ---- Price & stock ----
      Decimal price = null;
      if (pbesByProduct.containsKey(p.Id)) {
        price = pbesByProduct.get(p.Id).UnitPrice;
      }

      Boolean inStock = SafeFieldUtil.safeGetBoolean(p, 'In_Stock__c');
      String productUrl = SafeFieldUtil.safeGetString(p, 'Product_URL__c');
      String imageUrl = SafeFieldUtil.safeGetString(p, 'Image_URL__c');
      String customBrand = SafeFieldUtil.safeGetString(p, 'Brand__c');

      // ---- Build flat item ----
      Map<String, Object> item = new Map<String, Object>();

      item.put('objecttype', objectType);
      item.put('documentId', docId);

      // Core commerce fields
      item.put('ec_name', ecName);
      item.put('ec_product_id', productIdForEc);
      item.put('ec_category', ecCategories); // <-- LIST of category/hierarchy strings
      item.put('ec_brand', customBrand);

      if (price != null) {
        item.put('ec_price', price);
      }
      if (inStock != null) {
        item.put('ec_in_stock', inStock);
      }

      // Optional but useful
      if (productUrl != null) {
        item.put('ec_product_url', productUrl);
      }
      if (imageUrl != null) {
        item.put('ec_images', new List<String>{ imageUrl });
      }

      addOrUpdate.add(item);
    }

    return JSON.serialize(
      new Map<String, Object>{ 'addOrUpdate' => addOrUpdate }
    );
  }

  public String buildPartialMergeNdjson(
    Map<String, Decimal> priceBySku,
    Map<String, Boolean> inStockBySku
  ) {
    List<Object> arr = new List<Object>();

    Set<String> skus = new Set<String>();
    if (priceBySku != null) {
      skus.addAll(priceBySku.keySet());
    }
    if (inStockBySku != null) {
      skus.addAll(inStockBySku.keySet());
    }

    for (String sku : skus) {
      Map<String, Object> item = new Map<String, Object>();

      String objectType = 'Product'; // default
      String docId = objectType.toLowerCase() + '://' + sku;

      item.put('objecttype', objectType);
      item.put('documentId', docId);
      item.put('ec_product_id', sku);

      if (priceBySku != null && priceBySku.containsKey(sku)) {
        item.put('ec_price', priceBySku.get(sku));
      }
      if (inStockBySku != null && inStockBySku.containsKey(sku)) {
        item.put('ec_in_stock', inStockBySku.get(sku));
      }

      arr.add(item);
    }

    return JSON.serialize(new Map<String, Object>{ 'addOrMerge' => arr });
  }

  /**
   * Builds ALL category paths for a product as a list of strings.
   *
   * Example output for one hierarchy:
   *   ["Generators",
   *    "Generators|Diesel",
   *    "Generators|Diesel|200kW"]
   *
   * If a product is in multiple categories, we merge all paths and deduplicate.
   */
  private List<String> buildCategoryPathsForProduct(
    Id productId,
    List<ProductCategoryProduct> links,
    Map<Id, ProductCategory> catById
  ) {
    Set<String> pathsSet = new Set<String>();

    for (ProductCategoryProduct l : links) {
      if (l.ProductId != productId) {
        continue;
      }
      Id leafCatId = l.ProductCategoryId;
      if (leafCatId == null) {
        continue;
      }
      // Build chain from leaf to root
      List<String> chain = new List<String>();
      Id cur = leafCatId;
      Integer guard = 0;
      while (cur != null && guard++ < 10) {
        ProductCategory c = catById.get(cur);
        if (c == null) {
          break;
        }
        chain.add(c.Name); // leaf -> root
        cur = c.ParentCategoryId;
      }
      if (chain.isEmpty()) {
        continue;
      }

      // Reverse manually: root -> ... -> leaf
      List<String> reversed = new List<String>();
      for (Integer i = chain.size() - 1; i >= 0; i--) {
        reversed.add(chain[i]);
      }

      // Build cumulative paths using "|" as separator
      List<String> acc = new List<String>();
      for (String name : reversed) {
        acc.add(name);
        pathsSet.add(String.join(acc, '|'));
      }
    }

    return new List<String>(pathsSet);
  }
}
