public with sharing class CatalogBuyerGroupPayloadDecorator {
  public static String decorateFullUpdatePayload(
    String jsonPayload,
    Map<Id, CatalogBuyerGroupAccessSnapshot> snapshotsByProductId,
    String webStoreId
  ) {
    if (String.isBlank(jsonPayload)) {
      return jsonPayload;
    }

    Object rootObject = JSON.deserializeUntyped(jsonPayload);
    if (!(rootObject instanceof Map<String, Object>)) {
      throw new CatalogJobException(
        'Builder payload must deserialize into a JSON object.'
      );
    }

    Map<String, Object> root = (Map<String, Object>) rootObject;
    Object addOrUpdateObject = root.get('addOrUpdate');
    if (!(addOrUpdateObject instanceof List<Object>)) {
      return jsonPayload;
    }

    Map<String, CatalogBuyerGroupAccessSnapshot> snapshotsByEcProductId =
      CatalogBuyerGroupAccessResolver.indexSnapshotsByEcProductId(
        snapshotsByProductId,
        webStoreId
      );

    for (Object itemObject : (List<Object>) addOrUpdateObject) {
      if (!(itemObject instanceof Map<String, Object>)) {
        continue;
      }

      Map<String, Object> item = (Map<String, Object>) itemObject;
      String ecProductId = valueAsString(item.get('ec_product_id'));
      if (String.isBlank(ecProductId)) {
        continue;
      }

      CatalogBuyerGroupAccessSnapshot snapshot = snapshotsByEcProductId.containsKey(
          ecProductId
        )
        ? snapshotsByEcProductId.get(ecProductId)
        : CatalogBuyerGroupAccessResolver.createEmptySnapshot(
            null,
            ecProductId,
            webStoreId
          );

      item.put('sf_buyergroup_ids', snapshot.getSortedBuyerGroupIds());
      item.put('sf_buyergroup_names', snapshot.getSortedBuyerGroupNames());
      item.put('sf_webstore_id', snapshot.webStoreId);
    }

    return JSON.serialize(root);
  }

  private static String valueAsString(Object value) {
    return value == null ? null : String.valueOf(value);
  }
}
