public with sharing class CatalogJsonBuilderCommerce implements ICatalogJsonBuilder {
  public String buildFullUpdateNdjson(
    List<Product2> products,
    Map<Id, PricebookEntry> pbesByProduct
  ) {
    Set<Id> pids = new Set<Id>();
    for (Product2 p : products)
      pids.add(p.Id);
    List<ProductCategoryProduct> links = [
      SELECT ProductId, ProductCategoryId
      FROM ProductCategoryProduct
      WHERE ProductId IN :pids
    ];
    Set<Id> catIds = new Set<Id>();
    for (ProductCategoryProduct l : links)
      catIds.add(l.ProductCategoryId);
    Map<Id, ProductCategory> catById = new Map<Id, ProductCategory>(
      [
        SELECT Id, Name, ParentCategoryId
        FROM ProductCategory
        WHERE Id IN :catIds
      ]
    );
    List<Object> updateArr = new List<Object>();
    for (Product2 p : products) {
      List<String> allPaths = new List<String>();
      for (ProductCategoryProduct l : links)
        if (l.ProductId == p.Id)
          allPaths.addAll(buildPaths(catById, l.ProductCategoryId));
      Map<String, Object> fields = new Map<String, Object>();
      fields.put('ec_brand', p.get('Brand__c'));
      fields.put(
        'ec_price',
        pbesByProduct.containsKey(p.Id)
          ? pbesByProduct.get(p.Id).UnitPrice
          : null
      );
      fields.put('ec_category', new List<String>(new Set<String>(allPaths)));
      fields.put(
        'ec_images',
        p.get('Image_URL__c') != null
          ? new List<String>{ String.valueOf(p.get('Image_URL__c')) }
          : null
      );
      fields.put('ec_productUrl', String.valueOf(p.get('Product_URL__c')));
      fields.put('ec_in_stock', (Boolean) p.get('In_Stock__c'));
      Map<String, Object> doc = new Map<String, Object>{
        'title' => p.Name,
        'fields' => fields
      };
      updateArr.add(
        new Map<String, Object>{
          'documentId' => (String) (p.StockKeepingUnit != null
            ? p.StockKeepingUnit
            : (String) p.Id),
          'document' => doc
        }
      );
    }
    return JSON.serialize(new Map<String, Object>{ 'update' => updateArr });
  }
  public String buildPartialMergeNdjson(
    Map<String, Decimal> priceBySku,
    Map<String, Boolean> inStockBySku
  ) {
    List<Object> mergeArr = new List<Object>();
    Set<String> skus = new Set<String>();
    if (priceBySku != null)
      skus.addAll(priceBySku.keySet());
    if (inStockBySku != null)
      skus.addAll(inStockBySku.keySet());
    for (String sku : skus) {
      Map<String, Object> fields = new Map<String, Object>();
      if (priceBySku != null && priceBySku.containsKey(sku))
        fields.put('ec_price', priceBySku.get(sku));
      if (inStockBySku != null && inStockBySku.containsKey(sku))
        fields.put('ec_in_stock', inStockBySku.get(sku));
      mergeArr.add(
        new Map<String, Object>{
          'documentId' => sku,
          'document' => new Map<String, Object>{ 'fields' => fields }
        }
      );
    }
    return JSON.serialize(new Map<String, Object>{ 'merge' => mergeArr });
  }
  private List<String> buildPaths(Map<Id, ProductCategory> cats, Id leafId) {
    List<String> names = new List<String>();
    Id cur = leafId;
    Integer guard = 0;
    while (cur != null && guard++ < 10) {
      ProductCategory c = cats.get(cur);
      if (c == null)
        break;
      names.add(c.Name);
      cur = c.ParentCategoryId;
    }
    names.reverse();
    List<String> acc = new List<String>();
    List<String> paths = new List<String>();
    for (String n : names) {
      acc.add(n);
      paths.add(String.join(acc, '>'));
    }
    return paths;
  }
}
