/**
 * CatalogJsonBuilderVariant
 *
 * Builds Coveo Commerce JSON payloads for product variant use cases.
 * In the variant model, products have multiple SKU variants differentiated by
 * attributes like size, color, material, etc.
 *
 * Payload Structure for Variant Products:
 * {
 *   "objecttype": "Product",
 *   "documentId": "product://VARIANT-SKU",
 *   "ec_product_id": "VARIANT-SKU",
 *   "ec_name": "Product Name - Blue - Large",
 *   "ec_item_group_id": "PARENT-SKU",
 *   "ec_variant_id": "VARIANT-SKU",
 *   "sf_variant_color": "Blue",
 *   "sf_variant_size": "Large"
 * }
 *
 * Variant Attribute Fields (configured via AdditionalProductFields__c):
 * - Variant_Color__c -> sf_variant_color
 * - Variant_Size__c -> sf_variant_size
 * - Variant_Material__c -> sf_variant_material
 *
 * Configuration:
 * - Parent products: Type = 'Base' (or no Type set)
 * - Variant products: Type = 'Variation' with Parent_Product__c set
 * - Use AdditionalProductFields__c for variant attributes
 *
 * @see https://docs.coveo.com/en/m53g0506/coveo-for-commerce/catalog-variant-data-and-product-groupings
 */
public with sharing class CatalogJsonBuilderVariant implements ICatalogJsonBuilder {
  // Known variant attribute field patterns
  private static final Set<String> VARIANT_FIELD_PATTERNS = new Set<String>{
    'variant_',
    'color',
    'size',
    'material',
    'style',
    'pattern'
  };

  /**
   * Builds a full update payload with variant-level product data.
   * Variants include ec_variant_id and variant-specific attributes.
   *
   * @param products List of Product2 records (parents and variants)
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

    // Build parent product code lookup
    Map<Id, String> productCodeById = new Map<Id, String>();
    for (Product2 p : products) {
      productCodeById.put(
        p.Id,
        String.isNotBlank(p.ProductCode) ? p.ProductCode : (String) p.Id
      );
    }

    // Load parent codes for variants with parents outside current scope
    Set<Id> parentIds = new Set<Id>();
    for (Product2 p : products) {
      Id parentId = SafeFieldUtil.safeGetId(p, 'Parent_Product__c');
      if (parentId != null && !productCodeById.containsKey(parentId)) {
        parentIds.add(parentId);
      }
    }

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

    // Load category hierarchy
    Map<Id, List<String>> categoriesByProductId = loadCategoryHierarchy(
      products
    );

    List<Object> addOrUpdate = new List<Object>();

    for (Product2 p : products) {
      Map<String, Object> item = buildVariantItem(
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
   * Builds a product item with variant-specific fields.
   * Variants include ec_variant_id and variant attribute fields.
   *
   * @param p Product2 record
   * @param pbesByProduct Map of Product2 Id to PricebookEntry
   * @param extraFieldNames Additional fields to include
   * @param productCodeById Map of Product2 Id to ProductCode
   * @param categoriesByProductId Map of Product2 Id to category paths
   * @return Map representing the product/variant item
   */
  private Map<String, Object> buildVariantItem(
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

    // Determine if this is a variant (has parent and/or Type = 'Variation')
    Id parentId = SafeFieldUtil.safeGetId(p, 'Parent_Product__c');
    String productType = SafeFieldUtil.safeGetString(p, 'Type');
    Boolean isVariant =
      (parentId != null) || ('Variation'.equalsIgnoreCase(productType));

    // Set grouping fields
    if (parentId != null && productCodeById.containsKey(parentId)) {
      // Variant with parent - use parent's code as group id
      item.put('ec_item_group_id', productCodeById.get(parentId));
    } else {
      // Parent/standalone product - use own code as group id
      item.put('ec_item_group_id', productId);
    }

    // ec_variant_id: unique identifier for this specific variant
    // For variants, this is the variant's own SKU
    // For parent products, this can be omitted or set to own SKU
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

    // Process additional fields, identifying variant attributes specially
    if (extraFieldNames != null) {
      for (String apiName : extraFieldNames) {
        String trimmed = apiName != null ? apiName.trim() : null;
        if (String.isBlank(trimmed)) {
          continue;
        }

        Object val = SafeFieldUtil.safeGet(p, trimmed);
        if (val == null) {
          continue;
        }

        // Determine appropriate field name prefix
        String lowerName = trimmed.toLowerCase();
        String fieldKey;

        if (isVariantAttributeField(lowerName)) {
          // Variant attributes get sf_variant_ prefix for clarity
          fieldKey = 'sf_' + lowerName;
        } else {
          // Regular additional fields
          fieldKey = 'sf_' + lowerName;
        }

        item.put(fieldKey, val);
      }
    }

    // Add standard Salesforce variant fields if present
    addVariantAttribute(p, item, 'Variant_Color__c', 'ec_variant_color');
    addVariantAttribute(p, item, 'Variant_Size__c', 'ec_variant_size');
    addVariantAttribute(p, item, 'Variant_Material__c', 'ec_variant_material');

    return item;
  }

  /**
   * Checks if a field name appears to be a variant attribute.
   *
   * @param fieldName Lowercase field API name
   * @return true if this looks like a variant attribute field
   */
  private Boolean isVariantAttributeField(String fieldName) {
    for (String pattern : VARIANT_FIELD_PATTERNS) {
      if (fieldName.contains(pattern)) {
        return true;
      }
    }
    return false;
  }

  /**
   * Adds a variant attribute to the item if the field exists and has a value.
   *
   * @param p Product2 record
   * @param item Item map to add attribute to
   * @param sfFieldName Salesforce field API name
   * @param coveoFieldName Target Coveo field name
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
