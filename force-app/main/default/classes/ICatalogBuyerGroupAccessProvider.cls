public interface ICatalogBuyerGroupAccessProvider {
  List<String> getRequiredProductFieldsForBuyerGroupAccess();

  Map<Id, CatalogBuyerGroupAccessSnapshot> resolveBuyerGroupAccess(
    CatalogJobConfig__mdt jobConfig,
    List<Product2> products,
    Map<Id, String> ecProductIdByProductId
  );
}
