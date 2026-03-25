@IsTest
private class BuyerGroupAvailabilityPayloadBuilderTest {
  private static Id makeBuyerGroupId(Integer sequence) {
    String keyPrefix = BuyerGroup.SObjectType.getDescribe().getKeyPrefix();
    String id15 = keyPrefix + String.valueOf(sequence).leftPad(12, '0');
    return Id.valueOf(to18CharId(id15));
  }

  private static String to18CharId(String id15) {
    String suffixChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345';
    String suffix = '';

    for (Integer blockIndex = 0; blockIndex < 3; blockIndex++) {
      Integer flags = 0;

      for (Integer charIndex = 0; charIndex < 5; charIndex++) {
        Integer offset = (blockIndex * 5) + charIndex;
        String ch = id15.substring(offset, offset + 1);
        if (ch.equals(ch.toUpperCase()) && !ch.equals(ch.toLowerCase())) {
          flags += 1 << charIndex;
        }
      }

      suffix += suffixChars.substring(flags, flags + 1);
    }

    return id15 + suffix;
  }

  @IsTest
  static void testBuildFullUpdateNdjson_buildsAvailabilityItems() {
    Id buyerGroupId = makeBuyerGroupId(1);
    BuyerGroup buyerGroup = new BuyerGroup(
      Id = buyerGroupId,
      Name = 'Contract Buyers'
    );

    Map<Id, Set<String>> itemIdsByBuyerGroup = new Map<Id, Set<String>>{
      buyerGroup.Id => new Set<String>{ 'SKU-200', 'SKU-100' }
    };

    String payload = BuyerGroupAvailabilityPayloadBuilder.buildFullUpdateNdjson(
      new List<BuyerGroup>{ buyerGroup },
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
    Id buyerGroupId = makeBuyerGroupId(2);
    BuyerGroup buyerGroup = new BuyerGroup(
      Id = buyerGroupId,
      Name = 'No Products'
    );

    String payload = BuyerGroupAvailabilityPayloadBuilder.buildFullUpdateNdjson(
      new List<BuyerGroup>{ buyerGroup },
      new Map<Id, Set<String>>{ buyerGroup.Id => new Set<String>() },
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
