/**
 * CatalogJsonBuilderGroupingWithVariants
 *
 * Builds Coveo Commerce JSON payloads for the most complex catalog structure
 * where products have BOTH grouping relationships AND variant-level data.
 *
 * Three-tier hierarchy:
 * 1. Product Groups (families) - parent grouping containers
 * 2. Products - members of a group, can be parent of variants
 * 3. Variants - SKU-level items with specific attributes (size, color, etc.)
 *
 * Example Hierarchy:
 * - "Running Shoes" (Group)
 *   - "Nike Air Max" (Product in group)
 *     - "Nike Air Max - Blue - Size 10" (Variant of product)
 *     - "Nike Air Max - Red - Size 11" (Variant of product)
 *   - "Adidas UltraBoost" (Product in group)
 *     - "Adidas UltraBoost - White - Size 9" (Variant of product)
 *
 * Payload Structure:
 * {
 *   "objecttype": "Product",
 *   "documentId": "product://VARIANT-SKU",
 *   "ec_product_id": "VARIANT-SKU",
 *   "ec_name": "Nike Air Max - Blue - Size 10",
 *   "ec_item_group_id": "PRODUCT-SKU",       // Links to parent product
 *   "ec_variant_id": "VARIANT-SKU",          // Unique variant identifier
 *   "ec_product_family": "GROUP-SKU",        // Links to product group/family
 *   "ec_variant_color": "Blue",
 *   "ec_variant_size": "10"
 * }
 *
 * Configuration via Custom Fields:
 * - Product_Group__c: Reference to ProductGroup (for grouping relationship)
 * - Parent_Product__c: Reference to parent Product (for variant relationship)
 * - Type: 'Base' for parents, 'Variation' for variants
 *
 * @see https://docs.coveo.com/en/m53g0506/coveo-for-commerce/catalog-variant-data-and-product-groupings
 */
public with sharing class CatalogJsonBuilderGroupingWithVariants implements ICatalogJsonBuilder {
  /**
   * Builds a full update payload supporting both product groupings and variants.
   * Handles three-tier hierarchies: Group -> Product -> Variant
   *
   * @param products List of Product2 records (groups, products, and variants)
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

    // Build comprehensive product code lookup
    Map<Id, String> productCodeById = buildProductCodeMap(products);

    // Load category hierarchy
    Map<Id, List<String>> categoriesByProductId = loadCategoryHierarchy(
      products
    );

    List<Object> addOrUpdate = new List<Object>();

    for (Product2 p : products) {
      Map<String, Object> item = buildCombinedItem(
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
   * Builds a map of Product2 Id to ProductCode, including any referenced
   * parent products or product groups not in the current scope.
   *
   * @param products List of Product2 records
   * @return Map of Product2 Id to ProductCode
   */
  private Map<Id, String> buildProductCodeMap(List<Product2> products) {
    Map<Id, String> productCodeById = new Map<Id, String>();

    for (Product2 p : products) {
      productCodeById.put(
        p.Id,
        String.isNotBlank(p.ProductCode) ? p.ProductCode : (String) p.Id
      );
    }

    // Collect IDs of parents/groups not in current scope
    Set<Id> missingIds = new Set<Id>();
    for (Product2 p : products) {
      // Parent product (for variant relationship)
      Id parentId = SafeFieldUtil.safeGetId(p, 'Parent_Product__c');
      if (parentId != null && !productCodeById.containsKey(parentId)) {
        missingIds.add(parentId);
      }

      // Product group (for family/grouping relationship)
      Id groupId = SafeFieldUtil.safeGetId(p, 'Product_Group__c');
      if (groupId != null && !productCodeById.containsKey(groupId)) {
        missingIds.add(groupId);
      }
    }

    // Load missing product codes
    if (!missingIds.isEmpty()) {
      for (Product2 missing : [
        SELECT Id, ProductCode
        FROM Product2
        WHERE Id IN :missingIds
      ]) {
        productCodeById.put(
          missing.Id,
          String.isNotBlank(missing.ProductCode)
            ? missing.ProductCode
            : (String) missing.Id
        );
      }
    }

    return productCodeById;
  }

  /**
   * Builds a product item supporting both grouping and variant relationships.
   *
   * Relationship hierarchy:
   * - ec_product_family: Links to product group/family (grouping level)
   * - ec_item_group_id: Links to parent product (for variants)
   * - ec_variant_id: Unique variant identifier (for variants)
   *
   * @param p Product2 record
   * @param pbesByProduct Map of Product2 Id to PricebookEntry
   * @param extraFieldNames Additional fields to include
   * @param productCodeById Map of Product2 Id to ProductCode
   * @param categoriesByProductId Map of Product2 Id to category paths
   * @return Map representing the product item
   */
  private Map<String, Object> buildCombinedItem(
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

    // Determine product tier and set relationships
    Id parentId = SafeFieldUtil.safeGetId(p, 'Parent_Product__c');
    Id groupId = SafeFieldUtil.safeGetId(p, 'Product_Group__c');
    String productType = SafeFieldUtil.safeGetString(p, 'Type');
    Boolean isVariant =
      (parentId != null) || ('Variation'.equalsIgnoreCase(productType));

    // ec_item_group_id: Links variant to its parent product
    if (parentId != null && productCodeById.containsKey(parentId)) {
      item.put('ec_item_group_id', productCodeById.get(parentId));
    } else {
      // Not a variant - use own code as group id
      item.put('ec_item_group_id', productId);
    }

    // ec_product_family: Links product to its product group/family
    // This establishes the grouping relationship at a higher level
    if (groupId != null && productCodeById.containsKey(groupId)) {
      item.put('ec_product_family', productCodeById.get(groupId));
    }

    // ec_variant_id: Unique identifier for variants
    if (isVariant) {
      item.put('ec_variant_id', productId);
    }

    // Categories
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

    // Standard optional fields
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

    // Add variant-specific attributes
    addVariantAttribute(p, item, 'Variant_Color__c', 'ec_variant_color');
    addVariantAttribute(p, item, 'Variant_Size__c', 'ec_variant_size');
    addVariantAttribute(p, item, 'Variant_Material__c', 'ec_variant_material');
    addVariantAttribute(p, item, 'Variant_Style__c', 'ec_variant_style');

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
   * Adds a variant attribute to the item if the field exists and has a value.
   */
  private void addVariantAttribute(
    Product2 p,
    Map<String, Object> item,
    String sfFieldName,
    String coveoFieldName
  ) {
    String val = SafeFieldUtil.safeGetString(p, sfFieldName);
    if (val != null) {
      item.put(coveoFieldName, val);
    }
  }

  /**
   * Loads category hierarchy paths for all products.
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

    List<ProductCategoryProduct> links = [
      SELECT ProductId, ProductCategoryId
      FROM ProductCategoryProduct
      WHERE ProductId IN :productIds
    ];

    if (links.isEmpty()) {
      return result;
    }

    // Collect all category IDs and ancestors
    Set<Id> allCategoryIds = new Set<Id>();
    for (ProductCategoryProduct l : links) {
      if (l.ProductCategoryId != null) {
        allCategoryIds.add(l.ProductCategoryId);
      }
    }

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

    Map<Id, ProductCategory> categoryById = new Map<Id, ProductCategory>(
      [
        SELECT Id, Name, ParentCategoryId
        FROM ProductCategory
        WHERE Id IN :allCategoryIds
      ]
    );

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

    // Reverse to get root -> leaf
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
