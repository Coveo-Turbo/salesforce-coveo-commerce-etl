public with sharing class CatalogBuyerGroupPayloadDecorator {
  public static String decorateFullUpdatePayload(
    String jsonPayload,
    Map<Id, CatalogBuyerGroupAccessSnapshot> snapshotsByProductId,
    Set<Id> webStoreIds
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

    List<String> sortedWebStoreIds = new List<String>();
    if (webStoreIds != null) {
      for (Id webStoreId : webStoreIds) {
        sortedWebStoreIds.add(String.valueOf(webStoreId));
      }
      sortedWebStoreIds.sort();
    }
    String singleWebStoreId = sortedWebStoreIds.size() == 1
      ? sortedWebStoreIds[0]
      : null;

    Map<String, CatalogBuyerGroupAccessSnapshot> snapshotsByEcProductId = CatalogBuyerGroupAccessResolver.indexSnapshotsByEcProductId(
      snapshotsByProductId,
      singleWebStoreId
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
            singleWebStoreId
          );

      item.put('sf_buyergroup_ids', snapshot.getSortedBuyerGroupIds());
      item.put('sf_buyergroup_names', snapshot.getSortedBuyerGroupNames());
      item.put('sf_webstore_ids', sortedWebStoreIds);
      if (singleWebStoreId != null) {
        item.put('sf_webstore_id', singleWebStoreId);
      } else {
        item.remove('sf_webstore_id');
      }
    }

    return JSON.serialize(root);
  }

  /** Backward-compatible overload for callers passing a single web store ID. */
  public static String decorateFullUpdatePayload(
    String jsonPayload,
    Map<Id, CatalogBuyerGroupAccessSnapshot> snapshotsByProductId,
    String webStoreId
  ) {
    Set<Id> webStoreIds = new Set<Id>();
    if (String.isNotBlank(webStoreId)) {
      webStoreIds.add((Id) webStoreId);
    }
    return decorateFullUpdatePayload(
      jsonPayload,
      snapshotsByProductId,
      webStoreIds
    );
  }

  private static String valueAsString(Object value) {
    return value == null ? null : String.valueOf(value);
  }
}
