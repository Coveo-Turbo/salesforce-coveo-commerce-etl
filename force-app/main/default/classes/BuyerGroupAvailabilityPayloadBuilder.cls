public with sharing class BuyerGroupAvailabilityPayloadBuilder {
  public static String buildFullUpdateNdjson(
    List<SObject> buyerGroups,
    Map<Id, Set<String>> itemIdsByBuyerGroup,
    String webStoreId
  ) {
    List<Object> addOrUpdate = new List<Object>();

    for (SObject buyerGroup : buyerGroups) {
      Id buyerGroupId = (Id) buyerGroup.get('Id');
      String buyerGroupName = SafeFieldUtil.safeGetString(buyerGroup, 'Name');

      Set<String> itemIds = itemIdsByBuyerGroup.get(buyerGroupId);
      if (itemIds == null) {
        itemIds = new Set<String>();
      }

      List<String> sortedItemIds = new List<String>(itemIds);
      sortedItemIds.sort();

      Map<String, Object> item = new Map<String, Object>();
      item.put('objecttype', 'Availability');
      item.put('documentId', 'availability://' + String.valueOf(buyerGroupId));
      item.put('ec_availability_id', String.valueOf(buyerGroupId));
      item.put('ec_available_items', sortedItemIds);
      item.put('sf_webstore_id', webStoreId);

      if (String.isNotBlank(buyerGroupName)) {
        item.put('ec_name', buyerGroupName);
        item.put('sf_buyergroup_name', buyerGroupName);
      }

      addOrUpdate.add(item);
    }

    return JSON.serialize(
      new Map<String, Object>{ 'addOrUpdate' => addOrUpdate }
    );
  }
}
