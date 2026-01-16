public with sharing class CatalogJsonBuilderCommerce implements ICatalogJsonBuilder {
  public String buildFullUpdateNdjson(
    List<Product2> products,
    Map<Id, PricebookEntry> pbesByProduct,
    List<String> extraFieldNames
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

    System.debug(
      LoggingLevel.FINE,
      'Loaded ' +
        links.size() +
        ' ProductCategoryProduct links for ' +
        pids.size() +
        ' products'
    );

    // Collect all leaf category ids
    Set<Id> allCategoryIds = new Set<Id>();
    for (ProductCategoryProduct l : links) {
      if (l.ProductCategoryId != null) {
        allCategoryIds.add(l.ProductCategoryId);
      }
    }

    // Walk up parents to collect full chain of ancestors
    // We'll iteratively add ParentCategoryIds until no new ones appear
    Boolean changed = true;
    Integer guard = 0;
    while (changed && guard++ < 10 && !allCategoryIds.isEmpty()) {
      changed = false;

      // Load current batch of categories
      Map<Id, ProductCategory> batch = new Map<Id, ProductCategory>(
        [
          SELECT Id, ParentCategoryId
          FROM ProductCategory
          WHERE Id IN :allCategoryIds
        ]
      );

      Set<Id> newParents = new Set<Id>();
      for (ProductCategory c : batch.values()) {
        if (
          c.ParentCategoryId != null &&
          !allCategoryIds.contains(c.ParentCategoryId)
        ) {
          newParents.add(c.ParentCategoryId);
        }
      }

      if (!newParents.isEmpty()) {
        allCategoryIds.addAll(newParents);
        changed = true;
      }
    }

    // Finally load the full map of categories (all leaves + all ancestors)
    Map<Id, ProductCategory> catById = new Map<Id, ProductCategory>(
      [
        SELECT Id, Name, ParentCategoryId
        FROM ProductCategory
        WHERE Id IN :allCategoryIds
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

      // ---- ec_description ----
      String ecDescription = p.Description;

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
      item.put('ec_description', ecDescription);
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

      // Attach extra Product2 fields as metadata
      if (extraFieldNames != null && !extraFieldNames.isEmpty()) {
        for (String apiName : extraFieldNames) {
          String trimmed = apiName != null ? apiName.trim() : null;
          if (String.isBlank(trimmed)) {
            continue;
          }
          Object val = SafeFieldUtil.safeGet(p, trimmed);
          if (val == null) {
            continue;
          }
          // Prefix with sf_ to avoid collisions, keep lowercase for consistency
          String metaKey = 'sf_' + trimmed.toLowerCase();
          item.put(metaKey, val);
        }
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
    System.debug(
      LoggingLevel.FINE,
      'buildCategoryPathsForProduct: START productId=' + productId
    );
    System.debug(
      LoggingLevel.FINE,
      '  links.size=' + (links == null ? 0 : links.size())
    );
    System.debug(
      LoggingLevel.FINE,
      '  catById.size=' + (catById == null ? 0 : catById.size())
    );

    Set<String> pathsSet = new Set<String>();

    if (links == null || links.isEmpty()) {
      System.debug(
        LoggingLevel.FINE,
        '  No ProductCategoryProduct links provided.'
      );
      return new List<String>();
    }
    if (catById == null || catById.isEmpty()) {
      System.debug(LoggingLevel.FINE, '  No ProductCategory records provided.');
      return new List<String>();
    }

    for (ProductCategoryProduct l : links) {
      System.debug(
        LoggingLevel.FINE,
        '  link: ProductId=' +
          l.ProductId +
          ' / CategoryId=' +
          l.ProductCategoryId
      );
    }

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
          System.debug(
            LoggingLevel.FINE,
            '  Category not found in map for Id=' + cur
          );
          break;
        }
        chain.add(c.Name); // leaf -> root
        cur = c.ParentCategoryId;
      }
      if (chain.isEmpty()) {
        continue;
      }

      System.debug(LoggingLevel.FINE, '  chain (leaf->root)=' + chain);

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

    System.debug(
      LoggingLevel.FINE,
      'buildCategoryPathsForProduct: productId=' +
        productId +
        ' => paths=' +
        pathsSet
    );

    return new List<String>(pathsSet);
  }
}
