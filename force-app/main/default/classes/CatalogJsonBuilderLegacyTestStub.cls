@IsTest
public class CatalogJsonBuilderLegacyTestStub implements ICatalogJsonBuilder {
  public String buildFullUpdateNdjson(
    List<Product2> products,
    Map<Id, Map<String, Decimal>> pricesByProduct,
    List<String> extraFieldNames
  ) {
    List<Object> addOrUpdate = new List<Object>();

    for (Product2 product : products) {
      String ecProductId = CatalogProductIdentityResolver.resolveFallbackEcProductId(
        product
      );
      addOrUpdate.add(
        new Map<String, Object>{
          'objecttype' => 'Product',
          'documentId' => 'product://' + ecProductId,
          'ec_product_id' => ecProductId,
          'ec_name' => product.Name
        }
      );
    }

    return JSON.serialize(
      new Map<String, Object>{ 'addOrUpdate' => addOrUpdate }
    );
  }

  public String buildPartialMergeNdjson(
    Map<String, Decimal> priceBySku,
    Map<String, Boolean> inStockBySku
  ) {
    return JSON.serialize(
      new Map<String, Object>{ 'addOrMerge' => new List<Object>() }
    );
  }
}
