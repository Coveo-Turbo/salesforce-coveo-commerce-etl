public interface ICatalogProductIdentityProvider {
  List<String> getRequiredProductFieldsForIdentity();

  Map<Id, String> resolveEcProductIds(List<Product2> products);
}
