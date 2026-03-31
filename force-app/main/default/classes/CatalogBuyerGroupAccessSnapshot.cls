public class CatalogBuyerGroupAccessSnapshot {
  public Id productId;
  public String ecProductId;
  public String webStoreId;
  public Set<String> buyerGroupIds;
  public Set<String> buyerGroupNames;

  public CatalogBuyerGroupAccessSnapshot() {
    buyerGroupIds = new Set<String>();
    buyerGroupNames = new Set<String>();
  }

  public List<String> getSortedBuyerGroupIds() {
    List<String> sortedBuyerGroupIds = new List<String>(
      buyerGroupIds == null ? new Set<String>() : buyerGroupIds
    );
    sortedBuyerGroupIds.sort();
    return sortedBuyerGroupIds;
  }

  public List<String> getSortedBuyerGroupNames() {
    List<String> sortedBuyerGroupNames = new List<String>(
      buyerGroupNames == null ? new Set<String>() : buyerGroupNames
    );
    sortedBuyerGroupNames.sort();
    return sortedBuyerGroupNames;
  }
}
