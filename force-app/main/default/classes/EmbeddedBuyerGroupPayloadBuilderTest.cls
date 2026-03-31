@IsTest
private class EmbeddedBuyerGroupPayloadBuilderTest {
  @IsTest
  static void testBuildPartialUpdateJson_createsThreeReplaceOperationsPerProduct() {
    CatalogBuyerGroupAccessSnapshot firstSnapshot =
      new CatalogBuyerGroupAccessSnapshot();
    firstSnapshot.ecProductId = 'EC-401';
    firstSnapshot.webStoreId = 'store-401';
    firstSnapshot.buyerGroupIds.add('BG-2');
    firstSnapshot.buyerGroupIds.add('BG-1');
    firstSnapshot.buyerGroupNames.add('Beta');
    firstSnapshot.buyerGroupNames.add('Alpha');

    CatalogBuyerGroupAccessSnapshot secondSnapshot =
      new CatalogBuyerGroupAccessSnapshot();
    secondSnapshot.ecProductId = 'EC-402';
    secondSnapshot.webStoreId = 'store-402';

    String payload = EmbeddedBuyerGroupAccessPayloadBuilder.buildPartialUpdateJson(
      new List<CatalogBuyerGroupAccessSnapshot>{
        secondSnapshot,
        firstSnapshot
      }
    );

    Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(
      payload
    );
    List<Object> partialUpdate = (List<Object>) root.get('partialUpdate');
    Map<String, Object> firstOperation = (Map<String, Object>) partialUpdate[0];

    System.assertEquals(6, partialUpdate.size());
    System.assertEquals('product://EC-401', firstOperation.get('documentId'));
    System.assertEquals('fieldValueReplace', firstOperation.get('operator'));
    System.assertEquals('sf_buyergroup_ids', firstOperation.get('field'));
    System.assertEquals(
      JSON.serialize(new List<String>{ 'BG-1', 'BG-2' }),
      JSON.serialize((List<Object>) firstOperation.get('value'))
    );
  }

  @IsTest
  static void testBuildPartialUpdateJson_handlesEmptyInput() {
    String payload = EmbeddedBuyerGroupAccessPayloadBuilder.buildPartialUpdateJson(
      new List<CatalogBuyerGroupAccessSnapshot>()
    );

    System.assertEquals('{"partialUpdate":[]}', payload);
  }
}
