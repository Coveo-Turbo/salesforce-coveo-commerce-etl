/**
 * CatalogJsonBuilderDefault
 *
 * A simple default implementation of ICatalogJsonBuilder that produces basic
 * Coveo Commerce-compatible JSON payloads. Use this as a fallback or starting
 * point when no specific product organization strategy is required.
 *
 * Payload Structure:
 * - objecttype: "Product" for all items
 * - documentId: "product://{productId}"
 * - ec_name, ec_product_id, ec_description, ec_price, etc.
 *
 * This builder does NOT handle:
 * - Product groupings (parent-child relationships)
 * - Product variants (size, color, etc.)
 * - Category hierarchies (uses Family field as single category)
 *
 * @see https://docs.coveo.com/en/m53g0506/coveo-for-commerce/catalog-variant-data-and-product-groupings
 */
public with sharing class CatalogJsonBuilderDefault implements ICatalogJsonBuilder {
  /**
   * Builds a full update payload (addOrUpdate) for simple product exports.
   * Products are exported as flat items without variant or grouping logic.
   *
   * @param products List of Product2 records to export
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

    List<Object> addOrUpdate = new List<Object>();

    for (Product2 p : products) {
      Map<String, Object> item = buildProductItem(
        p,
        pbesByProduct,
        extraFieldNames
      );
      addOrUpdate.add(item);
    }

    return JSON.serialize(
      new Map<String, Object>{ 'addOrUpdate' => addOrUpdate }
    );
  }

  /**
   * Builds a partial merge payload (addOrMerge) for incremental updates.
   * Useful for price or stock updates without full product data refresh.
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
   * Builds a single product item as a Map for JSON serialization.
   *
   * @param p Product2 record
   * @param pbesByProduct Map of Product2 Id to PricebookEntry
   * @param extraFieldNames Additional fields to include
   * @return Map representing the product item
   */
  private Map<String, Object> buildProductItem(
    Product2 p,
    Map<Id, PricebookEntry> pbesByProduct,
    List<String> extraFieldNames
  ) {
    // Compute product identifier
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

    // Simple category from Family field (no hierarchy)
    if (String.isNotBlank(p.Family)) {
      item.put('ec_category', new List<String>{ p.Family });
    } else {
      item.put('ec_category', new List<String>{ 'Uncategorized' });
    }

    // Price from pricebook entry
    if (pbesByProduct != null && pbesByProduct.containsKey(p.Id)) {
      item.put('ec_price', pbesByProduct.get(p.Id).UnitPrice);
    }

    // Optional fields via SafeFieldUtil
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

    // Additional custom fields with sf_ prefix
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
}
