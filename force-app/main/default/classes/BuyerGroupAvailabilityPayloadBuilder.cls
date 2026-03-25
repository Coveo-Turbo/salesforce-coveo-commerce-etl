public with sharing class BuyerGroupAvailabilityPayloadBuilder {
  public static String buildFullUpdateNdjson(
    List<BuyerGroup> buyerGroups,
    Map<Id, Set<String>> itemIdsByBuyerGroup,
    String webStoreId
  ) {
    List<Object> addOrUpdate = new List<Object>();

    for (BuyerGroup buyerGroup : buyerGroups) {
      Set<String> itemIds = itemIdsByBuyerGroup.get(buyerGroup.Id);
      if (itemIds == null) {
        itemIds = new Set<String>();
      }

      List<String> sortedItemIds = new List<String>(itemIds);
      sortedItemIds.sort();

      Map<String, Object> item = new Map<String, Object>();
      item.put('objecttype', 'Availability');
      item.put('documentId', 'availability://' + String.valueOf(buyerGroup.Id));
      item.put('ec_availability_id', String.valueOf(buyerGroup.Id));
      item.put('ec_available_items', sortedItemIds);
      item.put('sf_webstore_id', webStoreId);

      if (String.isNotBlank(buyerGroup.Name)) {
        item.put('sf_buyergroup_name', buyerGroup.Name);
      }

      addOrUpdate.add(item);
    }

    return JSON.serialize(
      new Map<String, Object>{ 'addOrUpdate' => addOrUpdate }
    );
  }
}
