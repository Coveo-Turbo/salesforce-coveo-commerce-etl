@IsTest
private class CatalogBuyerGroupPayloadDecoratorTest {
  @IsTest
  static void testDecorateFullUpdatePayload_injectsEmbeddedAccessFields() {
    String snapshotWebStoreId = String.valueOf(Id.valueOf('0ZE000000000301'));
    String fallbackWebStoreId = String.valueOf(Id.valueOf('0ZE000000000302'));
    CatalogBuyerGroupAccessSnapshot snapshot = new CatalogBuyerGroupAccessSnapshot();
    snapshot.productId = Id.valueOf('01t000000000301AAA');
    snapshot.ecProductId = 'EC-301';
    snapshot.webStoreId = snapshotWebStoreId;
    snapshot.buyerGroupIds.add('BG-2');
    snapshot.buyerGroupIds.add('BG-1');
    snapshot.buyerGroupNames.add('Beta');
    snapshot.buyerGroupNames.add('Alpha');

    String decoratedPayload = CatalogBuyerGroupPayloadDecorator.decorateFullUpdatePayload(
      '{"addOrUpdate":[{"documentId":"product://EC-301","ec_product_id":"EC-301"},{"documentId":"product://EC-302","ec_product_id":"EC-302"}]}',
      new Map<Id, CatalogBuyerGroupAccessSnapshot>{
        snapshot.productId => snapshot
      },
      fallbackWebStoreId
    );

    Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(
      decoratedPayload
    );
    List<Object> documents = (List<Object>) root.get('addOrUpdate');
    Map<String, Object> firstDocument = (Map<String, Object>) documents[0];
    Map<String, Object> secondDocument = (Map<String, Object>) documents[1];

    System.assertEquals(
      JSON.serialize(new List<String>{ 'BG-1', 'BG-2' }),
      JSON.serialize((List<Object>) firstDocument.get('sf_buyergroup_ids'))
    );
    System.assertEquals(
      JSON.serialize(new List<String>{ 'Alpha', 'Beta' }),
      JSON.serialize((List<Object>) firstDocument.get('sf_buyergroup_names'))
    );
    System.assertEquals(
      fallbackWebStoreId,
      firstDocument.get('sf_webstore_id'),
      'The configured effective store scope should override legacy snapshot store values.'
    );
    System.assertEquals(
      JSON.serialize(new List<String>{ fallbackWebStoreId }),
      JSON.serialize((List<Object>) firstDocument.get('sf_webstore_ids'))
    );
    System.assertEquals(
      JSON.serialize(new List<Object>()),
      JSON.serialize((List<Object>) secondDocument.get('sf_buyergroup_ids'))
    );
    System.assertEquals(
      fallbackWebStoreId,
      secondDocument.get('sf_webstore_id')
    );
  }

  @IsTest
  static void testDecorateFullUpdatePayload_returnsOriginalWhenNoAddOrUpdate() {
    String webStoreId = String.valueOf(Id.valueOf('0ZE000000000303'));
    String inputPayload = '{"partialUpdate":[]}';

    System.assertEquals(
      inputPayload,
      CatalogBuyerGroupPayloadDecorator.decorateFullUpdatePayload(
        inputPayload,
        new Map<Id, CatalogBuyerGroupAccessSnapshot>(),
        webStoreId
      )
    );
  }
}
