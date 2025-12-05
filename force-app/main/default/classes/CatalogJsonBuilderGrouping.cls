/**
 * CatalogJsonBuilderGrouping
 *
 * Builds Coveo Commerce JSON payloads for product grouping use cases.
 * In the grouping model, products are organized into families/groups where:
 *
 * - A parent "group" product represents a product family
 * - Child products reference their parent via ec_item_group_id
 * - Group-level attributes (name, image, description) propagate from parent
 *
 * Payload Structure for Parent Products:
 * {
 *   "objecttype": "Product",
 *   "documentId": "product://PARENT-SKU",
 *   "ec_product_id": "PARENT-SKU",
 *   "ec_name": "Product Family Name",
 *   "ec_item_group_id": "PARENT-SKU"
 * }
 *
 * Payload Structure for Child Products:
 * {
 *   "objecttype": "Product",
 *   "documentId": "product://CHILD-SKU",
 *   "ec_product_id": "CHILD-SKU",
 *   "ec_name": "Child Product Name",
 *   "ec_item_group_id": "PARENT-SKU"
 * }
 *
 * Configuration:
 * - Products with no Parent_Product__c are treated as group parents
 * - Products with Parent_Product__c reference their parent's ProductCode
 *
 * @see https://docs.coveo.com/en/m53g0506/coveo-for-commerce/catalog-variant-data-and-product-groupings
 */
public with sharing class CatalogJsonBuilderGrouping implements ICatalogJsonBuilder {
  /**
   * Builds a full update payload supporting product grouping relationships.
   * Parent products are indexed as group heads; children reference parents via ec_item_group_id.
   *
   * @param products List of Product2 records (both parents and children)
   * @param pbesByProduct Map of Product2 Id to PricebookEntry for pricing
   * @param extraFieldNames List of additional Product2 field API names to include
   * @return JSON string with addOrUpdate array
   */
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

    // Build a map of Product Id -> ProductCode for parent lookup
    Map<Id, String> productCodeById = new Map<Id, String>();
    for (Product2 p : products) {
      productCodeById.put(
        p.Id,
        String.isNotBlank(p.ProductCode) ? p.ProductCode : (String) p.Id
      );
    }

    // Query parent product codes for children that have Parent_Product__c set
    Set<Id> parentIds = new Set<Id>();
    for (Product2 p : products) {
      Id parentId = SafeFieldUtil.safeGetId(p, 'Parent_Product__c');
      if (parentId != null && !productCodeById.containsKey(parentId)) {
        parentIds.add(parentId);
      }
    }

    // Load parent product codes if any are outside the current scope
    if (!parentIds.isEmpty()) {
      for (Product2 parent : [
        SELECT Id, ProductCode
        FROM Product2
        WHERE Id IN :parentIds
      ]) {
        productCodeById.put(
          parent.Id,
          String.isNotBlank(parent.ProductCode)
            ? parent.ProductCode
            : (String) parent.Id
        );
      }
    }

    // Load category hierarchy for all products
    Map<Id, List<String>> categoriesByProductId = loadCategoryHierarchy(
      products
    );

    List<Object> addOrUpdate = new List<Object>();

    for (Product2 p : products) {
      Map<String, Object> item = buildGroupingItem(
        p,
        pbesByProduct,
        extraFieldNames,
        productCodeById,
        categoriesByProductId
      );
      addOrUpdate.add(item);
    }

    return JSON.serialize(
      new Map<String, Object>{ 'addOrUpdate' => addOrUpdate }
    );
  }

  /**
   * Builds a partial merge payload for incremental updates.
   *
   * @param priceBySku Map of SKU to new price
   * @param inStockBySku Map of SKU to stock availability
   * @return JSON string with addOrMerge array
   */
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
      item.put('objecttype', 'Product');
      item.put('documentId', 'product://' + sku);
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
   * Builds a product item with grouping relationship support.
   * Sets ec_item_group_id to establish parent-child relationships.
   *
   * @param p Product2 record
   * @param pbesByProduct Map of Product2 Id to PricebookEntry
   * @param extraFieldNames Additional fields to include
   * @param productCodeById Map of Product2 Id to ProductCode for parent lookup
   * @param categoriesByProductId Map of Product2 Id to category paths
   * @return Map representing the product item with grouping fields
   */
  private Map<String, Object> buildGroupingItem(
    Product2 p,
    Map<Id, PricebookEntry> pbesByProduct,
    List<String> extraFieldNames,
    Map<Id, String> productCodeById,
    Map<Id, List<String>> categoriesByProductId
  ) {
    String productId = String.isNotBlank(p.ProductCode)
      ? p.ProductCode
      : (String) p.Id;

    Map<String, Object> item = new Map<String, Object>();

    // Core Coveo fields
    item.put('objecttype', 'Product');
    item.put('documentId', 'product://' + productId);
    item.put('ec_product_id', productId);
    item.put('ec_name', p.Name);

    if (String.isNotBlank(p.Description)) {
      item.put('ec_description', p.Description);
    }

    // Determine grouping relationship
    // ec_item_group_id links products to their parent group
    Id parentId = SafeFieldUtil.safeGetId(p, 'Parent_Product__c');
    if (parentId != null && productCodeById.containsKey(parentId)) {
      // This is a child product - reference parent's ProductCode
      item.put('ec_item_group_id', productCodeById.get(parentId));
    } else {
      // This is a parent/standalone product - use own ProductCode as group id
      item.put('ec_item_group_id', productId);
    }

    // Categories from hierarchy or fallback to Family
    List<String> categories = categoriesByProductId.get(p.Id);
    if (categories != null && !categories.isEmpty()) {
      item.put('ec_category', categories);
    } else if (String.isNotBlank(p.Family)) {
      item.put('ec_category', new List<String>{ p.Family });
    } else {
      item.put('ec_category', new List<String>{ 'Uncategorized' });
    }

    // Price
    if (pbesByProduct != null && pbesByProduct.containsKey(p.Id)) {
      item.put('ec_price', pbesByProduct.get(p.Id).UnitPrice);
    }

    // Optional fields
    Boolean inStock = SafeFieldUtil.safeGetBoolean(p, 'In_Stock__c');
    if (inStock != null) {
      item.put('ec_in_stock', inStock);
    }

    String productUrl = SafeFieldUtil.safeGetString(p, 'Product_URL__c');
    if (productUrl != null) {
      item.put('ec_product_url', productUrl);
    }

    String imageUrl = SafeFieldUtil.safeGetString(p, 'Image_URL__c');
    if (imageUrl != null) {
      item.put('ec_images', new List<String>{ imageUrl });
    }

    String brand = SafeFieldUtil.safeGetString(p, 'Brand__c');
    if (brand != null) {
      item.put('ec_brand', brand);
    }

    // Additional custom fields
    if (extraFieldNames != null) {
      for (String apiName : extraFieldNames) {
        String trimmed = apiName != null ? apiName.trim() : null;
        if (String.isBlank(trimmed)) {
          continue;
        }
        Object val = SafeFieldUtil.safeGet(p, trimmed);
        if (val != null) {
          item.put('sf_' + trimmed.toLowerCase(), val);
        }
      }
    }

    return item;
  }

  /**
   * Loads category hierarchy paths for all products using B2B Commerce categories.
   *
   * @param products List of Product2 records
   * @return Map of Product2 Id to list of category path strings
   */
  private Map<Id, List<String>> loadCategoryHierarchy(List<Product2> products) {
    Map<Id, List<String>> result = new Map<Id, List<String>>();

    if (products.isEmpty()) {
      return result;
    }

    Set<Id> productIds = new Set<Id>();
    for (Product2 p : products) {
      productIds.add(p.Id);
      result.put(p.Id, new List<String>());
    }

    // Load product-category junctions
    List<ProductCategoryProduct> links = [
      SELECT ProductId, ProductCategoryId
      FROM ProductCategoryProduct
      WHERE ProductId IN :productIds
    ];

    if (links.isEmpty()) {
      return result;
    }

    // Collect all category IDs and their ancestors
    Set<Id> allCategoryIds = new Set<Id>();
    for (ProductCategoryProduct l : links) {
      if (l.ProductCategoryId != null) {
        allCategoryIds.add(l.ProductCategoryId);
      }
    }

    // Walk up to collect all ancestor categories
    Boolean changed = true;
    Integer guard = 0;
    while (changed && guard++ < 10 && !allCategoryIds.isEmpty()) {
      changed = false;
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

    // Load all categories with names
    Map<Id, ProductCategory> categoryById = new Map<Id, ProductCategory>(
      [
        SELECT Id, Name, ParentCategoryId
        FROM ProductCategory
        WHERE Id IN :allCategoryIds
      ]
    );

    // Build category paths for each product
    for (ProductCategoryProduct link : links) {
      if (link.ProductCategoryId == null) {
        continue;
      }

      List<String> paths = buildCategoryPaths(
        link.ProductCategoryId,
        categoryById
      );
      List<String> existing = result.get(link.ProductId);
      if (existing != null) {
        for (String path : paths) {
          if (!existing.contains(path)) {
            existing.add(path);
          }
        }
      }
    }

    return result;
  }

  /**
   * Builds cumulative category paths from leaf to root.
   *
   * @param leafCategoryId Starting category ID
   * @param categoryById Map of all categories
   * @return List of category path strings (e.g., ["Tools", "Tools|Power Tools", "Tools|Power Tools|Drills"])
   */
  private List<String> buildCategoryPaths(
    Id leafCategoryId,
    Map<Id, ProductCategory> categoryById
  ) {
    List<String> chain = new List<String>();
    Id current = leafCategoryId;
    Integer guard = 0;

    while (current != null && guard++ < 10) {
      ProductCategory cat = categoryById.get(current);
      if (cat == null) {
        break;
      }
      chain.add(cat.Name);
      current = cat.ParentCategoryId;
    }

    if (chain.isEmpty()) {
      return new List<String>();
    }

    // Reverse to get root -> leaf order
    List<String> reversed = new List<String>();
    for (Integer i = chain.size() - 1; i >= 0; i--) {
      reversed.add(chain[i]);
    }

    // Build cumulative paths
    List<String> paths = new List<String>();
    List<String> accumulator = new List<String>();
    for (String name : reversed) {
      accumulator.add(name);
      paths.add(String.join(accumulator, '|'));
    }

    return paths;
  }
}
