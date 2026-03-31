@IsTest
public class CatalogJsonBuilderBrokenIdentityTestStub
  implements ICatalogJsonBuilder, ICatalogProductIdentityProvider {
  public List<String> getRequiredProductFieldsForIdentity() {
    return new List<String>{ 'ProductCode' };
  }

  public Map<Id, String> resolveEcProductIds(List<Product2> products) {
    Map<Id, String> resolvedIds = new Map<Id, String>();

    if (products == null || products.isEmpty()) {
      return resolvedIds;
    }

    resolvedIds.put(products[0].Id, '');

    for (Integer i = 1; i < products.size(); i++) {
      resolvedIds.put(products[i].Id, 'BROKEN-' + i);
    }

    return resolvedIds;
  }

  public String buildFullUpdateNdjson(
    List<Product2> products,
    Map<Id, Map<String, Decimal>> pricesByProduct,
    List<String> extraFieldNames
  ) {
    return JSON.serialize(
      new Map<String, Object>{ 'addOrUpdate' => new List<Object>() }
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
