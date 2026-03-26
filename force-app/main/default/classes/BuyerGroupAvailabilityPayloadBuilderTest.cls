@IsTest
private class BuyerGroupAvailabilityPayloadBuilderTest {
  @IsTest
  static void testBuildFullUpdateNdjson_buildsAvailabilityItems() {
    Id buyerGroupId = Id.valueOf('001000000000001AAA');
    SObject buyerGroup = new Account(
      Id = buyerGroupId,
      Name = 'Contract Buyers'
    );

    Map<Id, Set<String>> itemIdsByBuyerGroup = new Map<Id, Set<String>>{
      buyerGroupId => new Set<String>{ 'SKU-200', 'SKU-100' }
    };

    String payload = BuyerGroupAvailabilityPayloadBuilder.buildFullUpdateNdjson(
      new List<SObject>{ buyerGroup },
      itemIdsByBuyerGroup,
      '0ZE000000000001AAA'
    );

    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
      payload
    );
    List<Object> items = (List<Object>) body.get('addOrUpdate');
    System.assertEquals(1, items.size(), 'One availability item should exist');

    Map<String, Object> item = (Map<String, Object>) items[0];
    System.assertEquals('Availability', item.get('objecttype'));
    System.assertEquals(
      'availability://' + String.valueOf(buyerGroupId),
      item.get('documentId')
    );
    System.assertEquals(
      String.valueOf(buyerGroupId),
      item.get('ec_availability_id')
    );
    System.assertEquals('0ZE000000000001AAA', item.get('sf_webstore_id'));
    System.assertEquals('Contract Buyers', item.get('sf_buyergroup_name'));

    List<Object> availableItems = (List<Object>) item.get('ec_available_items');
    System.assertEquals(
      2,
      availableItems.size(),
      'All available items should be present'
    );
    System.assertEquals('SKU-100', (String) availableItems[0]);
    System.assertEquals('SKU-200', (String) availableItems[1]);
  }

  @IsTest
  static void testBuildFullUpdateNdjson_keepsEmptyBuyerGroups() {
    Id buyerGroupId = Id.valueOf('001000000000002AAA');
    SObject buyerGroup = new Account(Id = buyerGroupId, Name = 'No Products');

    String payload = BuyerGroupAvailabilityPayloadBuilder.buildFullUpdateNdjson(
      new List<SObject>{ buyerGroup },
      new Map<Id, Set<String>>{ buyerGroupId => new Set<String>() },
      '0ZE000000000001AAA'
    );

    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
      payload
    );
    List<Object> items = (List<Object>) body.get('addOrUpdate');
    System.assertEquals(
      1,
      items.size(),
      'Buyer Groups without items should still be exported'
    );

    Map<String, Object> item = (Map<String, Object>) items[0];
    System.assertEquals(
      'availability://' + String.valueOf(buyerGroupId),
      item.get('documentId')
    );
    List<Object> availableItems = (List<Object>) item.get('ec_available_items');
    System.assertEquals(
      0,
      availableItems.size(),
      'Empty Buyer Groups should export an empty available-items list'
    );
  }
}
