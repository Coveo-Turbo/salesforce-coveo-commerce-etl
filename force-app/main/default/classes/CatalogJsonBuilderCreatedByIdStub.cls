@IsTest
public class CatalogJsonBuilderCreatedByIdStub
  implements ICatalogJsonBuilder, ICatalogProductIdentityProvider {
  public List<String> getRequiredProductFieldsForIdentity() {
    return new List<String>{ 'CreatedById' };
  }

  public Map<Id, String> resolveEcProductIds(List<Product2> products) {
    Map<Id, String> resolvedIds = new Map<Id, String>();

    for (Product2 product : products) {
      resolvedIds.put(product.Id, String.valueOf(product.get('CreatedById')));
    }

    return resolvedIds;
  }

  public String buildFullUpdateNdjson(
    List<Product2> products,
    Map<Id, Map<String, Decimal>> pricesByProduct,
    List<String> extraFieldNames
  ) {
    Map<Id, String> ecProductIdByProductId = resolveEcProductIds(products);
    List<Object> addOrUpdate = new List<Object>();

    for (Product2 product : products) {
      String ecProductId = ecProductIdByProductId.get(product.Id);
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
