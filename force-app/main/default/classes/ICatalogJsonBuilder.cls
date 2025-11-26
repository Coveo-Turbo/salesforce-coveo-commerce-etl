public interface ICatalogJsonBuilder {
  /** Build a FULL update payload (JSON) for the given products */
  String buildFullUpdateNdjson(
    List<Product2> products,
    Map<Id, PricebookEntry> pbesByProduct,
    List<String> extraFieldNames
  );

  /** Build a PARTIAL merge payload (JSON) for deltas like price/stock */
  String buildPartialMergeNdjson(
    Map<String, Decimal> priceBySku,
    Map<String, Boolean> inStockBySku
  );
}
