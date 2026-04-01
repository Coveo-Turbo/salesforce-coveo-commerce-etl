public with sharing class CatalogBuyerGroupAccessResolver {
  public static ICatalogBuyerGroupAccessProvider getProvider(
    CatalogJobConfig__mdt jobConfig
  ) {
    return getProvider(CatalogProductIdentityResolver.getBuilder(jobConfig));
  }

  public static ICatalogBuyerGroupAccessProvider getProvider(
    ICatalogJsonBuilder builder
  ) {
    if (builder instanceof ICatalogBuyerGroupAccessProvider) {
      return (ICatalogBuyerGroupAccessProvider) builder;
    }

    return new CatalogBuyerGroupEntitlementProvider();
  }

  public static List<String> getRequiredProductFields(
    CatalogJobConfig__mdt jobConfig
  ) {
    return getRequiredProductFields(CatalogProductIdentityResolver.getBuilder(jobConfig));
  }

  public static List<String> getRequiredProductFields(ICatalogJsonBuilder builder) {
    List<String> fields = new List<String>();
    List<String> providerFields = getProvider(builder)
      .getRequiredProductFieldsForBuyerGroupAccess();

    if (providerFields == null) {
      return fields;
    }

    for (String fieldName : providerFields) {
      addFieldIfMissing(fields, fieldName);
    }

    return fields;
  }

  public static Map<Id, CatalogBuyerGroupAccessSnapshot> resolveBuyerGroupAccess(
    CatalogJobConfig__mdt jobConfig,
    List<Product2> products
  ) {
    ICatalogJsonBuilder builder = CatalogProductIdentityResolver.getBuilder(
      jobConfig
    );
    return resolveBuyerGroupAccess(jobConfig, products, builder);
  }

  public static Map<Id, CatalogBuyerGroupAccessSnapshot> resolveBuyerGroupAccess(
    CatalogJobConfig__mdt jobConfig,
    List<Product2> products,
    ICatalogJsonBuilder builder
  ) {
    return resolveBuyerGroupAccess(
      jobConfig,
      products,
      CatalogProductIdentityResolver.resolveEcProductIds(builder, products),
      builder
    );
  }

  public static Map<Id, CatalogBuyerGroupAccessSnapshot> resolveBuyerGroupAccess(
    CatalogJobConfig__mdt jobConfig,
    List<Product2> products,
    Map<Id, String> ecProductIdByProductId,
    ICatalogJsonBuilder builder
  ) {
    return normalizeSnapshots(
      products,
      ecProductIdByProductId,
      getProvider(builder).resolveBuyerGroupAccess(
        jobConfig,
        products,
        ecProductIdByProductId
      ),
      jobConfig == null ? null : jobConfig.WebStoreId__c
    );
  }

  public static Map<String, CatalogBuyerGroupAccessSnapshot> indexSnapshotsByEcProductId(
    Map<Id, CatalogBuyerGroupAccessSnapshot> snapshotsByProductId,
    String webStoreId
  ) {
    Map<String, CatalogBuyerGroupAccessSnapshot> snapshotsByEcProductId =
      new Map<String, CatalogBuyerGroupAccessSnapshot>();

    if (snapshotsByProductId == null) {
      return snapshotsByEcProductId;
    }

    for (CatalogBuyerGroupAccessSnapshot snapshot : snapshotsByProductId.values()) {
      if (snapshot == null || String.isBlank(snapshot.ecProductId)) {
        continue;
      }

      if (!snapshotsByEcProductId.containsKey(snapshot.ecProductId)) {
        snapshotsByEcProductId.put(
          snapshot.ecProductId,
          createEmptySnapshot(snapshot.productId, snapshot.ecProductId, webStoreId)
        );
      }

      CatalogBuyerGroupAccessSnapshot mergedSnapshot =
        snapshotsByEcProductId.get(snapshot.ecProductId);
      if (snapshot.buyerGroupIds != null) {
        mergedSnapshot.buyerGroupIds.addAll(snapshot.buyerGroupIds);
      }
      if (snapshot.buyerGroupNames != null) {
        mergedSnapshot.buyerGroupNames.addAll(snapshot.buyerGroupNames);
      }
      if (String.isNotBlank(snapshot.webStoreId)) {
        mergedSnapshot.webStoreId = snapshot.webStoreId;
      }
    }

    return snapshotsByEcProductId;
  }

  public static CatalogBuyerGroupAccessSnapshot createEmptySnapshot(
    Id productId,
    String ecProductId,
    String webStoreId
  ) {
    CatalogBuyerGroupAccessSnapshot snapshot = new CatalogBuyerGroupAccessSnapshot();
    snapshot.productId = productId;
    snapshot.ecProductId = ecProductId;
    snapshot.webStoreId = webStoreId;
    return snapshot;
  }

  @TestVisible
  private static Map<Id, CatalogBuyerGroupAccessSnapshot> normalizeSnapshots(
    List<Product2> products,
    Map<Id, String> ecProductIdByProductId,
    Map<Id, CatalogBuyerGroupAccessSnapshot> providerSnapshots,
    String webStoreId
  ) {
    Map<Id, CatalogBuyerGroupAccessSnapshot> normalizedSnapshots =
      new Map<Id, CatalogBuyerGroupAccessSnapshot>();

    if (products == null || products.isEmpty()) {
      return normalizedSnapshots;
    }

    if (providerSnapshots == null) {
      providerSnapshots = new Map<Id, CatalogBuyerGroupAccessSnapshot>();
    }

    for (Product2 product : products) {
      if (
        product == null ||
        product.Id == null ||
        ecProductIdByProductId == null ||
        !ecProductIdByProductId.containsKey(product.Id)
      ) {
        continue;
      }

      CatalogBuyerGroupAccessSnapshot snapshot = providerSnapshots.get(product.Id);
      if (snapshot == null) {
        snapshot = createEmptySnapshot(
          product.Id,
          ecProductIdByProductId.get(product.Id),
          webStoreId
        );
      }

      snapshot.productId = product.Id;
      snapshot.ecProductId = ecProductIdByProductId.get(product.Id);
      if (String.isBlank(snapshot.webStoreId)) {
        snapshot.webStoreId = webStoreId;
      }
      if (snapshot.buyerGroupIds == null) {
        snapshot.buyerGroupIds = new Set<String>();
      }
      if (snapshot.buyerGroupNames == null) {
        snapshot.buyerGroupNames = new Set<String>();
      }

      normalizedSnapshots.put(product.Id, snapshot);
    }

    return normalizedSnapshots;
  }

  private static void addFieldIfMissing(List<String> fields, String fieldName) {
    if (String.isBlank(fieldName)) {
      return;
    }

    String trimmed = fieldName.trim();
    if (String.isNotBlank(trimmed) && !fields.contains(trimmed)) {
      fields.add(trimmed);
    }
  }
}
