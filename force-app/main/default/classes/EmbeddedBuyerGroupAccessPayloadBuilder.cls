public with sharing class EmbeddedBuyerGroupAccessPayloadBuilder {
  public static String buildPartialUpdateJson(
    List<CatalogBuyerGroupAccessSnapshot> snapshots
  ) {
    List<Object> partialUpdate = new List<Object>();

    if (snapshots == null || snapshots.isEmpty()) {
      return JSON.serialize(
        new Map<String, Object>{ 'partialUpdate' => partialUpdate }
      );
    }

    Map<String, CatalogBuyerGroupAccessSnapshot> snapshotsByEcProductId = new Map<String, CatalogBuyerGroupAccessSnapshot>();
    List<String> sortedEcProductIds = new List<String>();

    for (CatalogBuyerGroupAccessSnapshot snapshot : snapshots) {
      if (snapshot == null || String.isBlank(snapshot.ecProductId)) {
        continue;
      }

      snapshotsByEcProductId.put(snapshot.ecProductId, snapshot);
      sortedEcProductIds.add(snapshot.ecProductId);
    }

    sortedEcProductIds.sort();

    for (String ecProductId : sortedEcProductIds) {
      CatalogBuyerGroupAccessSnapshot snapshot = snapshotsByEcProductId.get(
        ecProductId
      );
      String documentId = 'product://' + ecProductId;

      partialUpdate.add(
        buildFieldReplaceOperation(
          documentId,
          'sf_buyergroup_ids',
          snapshot.getSortedBuyerGroupIds()
        )
      );
      partialUpdate.add(
        buildFieldReplaceOperation(
          documentId,
          'sf_buyergroup_names',
          snapshot.getSortedBuyerGroupNames()
        )
      );
      partialUpdate.add(
        buildFieldReplaceOperation(
          documentId,
          'sf_webstore_ids',
          snapshot.getSortedWebStoreIds()
        )
      );
      if (snapshot.webStoreIds != null && snapshot.webStoreIds.size() == 1) {
        partialUpdate.add(
          buildFieldReplaceOperation(
            documentId,
            'sf_webstore_id',
            snapshot.webStoreId
          )
        );
      }
    }

    return JSON.serialize(
      new Map<String, Object>{ 'partialUpdate' => partialUpdate }
    );
  }

  private static Map<String, Object> buildFieldReplaceOperation(
    String documentId,
    String fieldName,
    Object value
  ) {
    return new Map<String, Object>{
      'documentId' => documentId,
      'operator' => 'fieldValueReplace',
      'field' => fieldName,
      'value' => value
    };
  }
}
