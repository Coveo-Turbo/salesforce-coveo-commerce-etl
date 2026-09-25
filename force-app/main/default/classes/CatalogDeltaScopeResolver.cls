public with sharing class CatalogDeltaScopeResolver {
  private static final Integer MAX_HIERARCHY_DEPTH = 20;
  private static final Map<String, SObjectField> PRODUCT_FIELDS = Product2.SObjectType
    .getDescribe()
    .fields.getMap();

  // Retained for source compatibility with callers that format completed
  // metrics. Scope discovery itself is now persisted and asynchronous.
  public class ScopeMetrics {
    public Integer impactedProductCount { get; set; }
    public Integer rootProductCount { get; set; }
    public Integer exportProductCount { get; set; }
  }

  public static Set<Id> resolveExportProductIds(
    CatalogJobConfig__mdt jobConfig,
    Datetime lowerExclusive,
    Datetime upperInclusive
  ) {
    throw new CatalogJobException(
      'Synchronous delta scope resolution is no longer supported. Launch the persisted delta pipeline through CatalogJobRunner.'
    );
  }

  public static ScopeMetrics describeScope(
    CatalogJobConfig__mdt jobConfig,
    Datetime lowerExclusive,
    Datetime upperInclusive
  ) {
    throw new CatalogJobException(
      'Synchronous delta scope metrics are no longer supported. Poll CatalogJobRunner.getDeltaRunSnapshots instead.'
    );
  }

  public static Boolean usesParentHierarchy(CatalogJobConfig__mdt jobConfig) {
    ICatalogJsonBuilder builder = CatalogProductIdentityResolver.getBuilder(
      jobConfig
    );
    return builder instanceof CatalogJsonBuilderGrouping ||
      builder instanceof CatalogJsonBuilderVariant ||
      builder instanceof CatalogJsonBuilderGroupingWithVariants;
  }

  public static Boolean usesProductGroupRoots(
    CatalogJobConfig__mdt jobConfig
  ) {
    return CatalogProductIdentityResolver.getBuilder(jobConfig) instanceof CatalogJsonBuilderGroupingWithVariants;
  }

  /**
   * Resolves roots for one bounded stage scope. The stage batch is capped at
   * 500 products, so its optional relationship walk cannot materialize an
   * unbounded delta window in one transaction.
   */
  public static Set<Id> resolveRootProductIds(
    CatalogJobConfig__mdt jobConfig,
    Set<Id> changedProductIds
  ) {
    Set<Id> rootIds = new Set<Id>();
    if (changedProductIds == null || changedProductIds.isEmpty()) {
      return rootIds;
    }

    Boolean hasParentHierarchy = usesParentHierarchy(jobConfig);
    Boolean hasProductGroupRoots = usesProductGroupRoots(jobConfig);
    if (!hasParentHierarchy && !hasProductGroupRoots) {
      rootIds.addAll(changedProductIds);
      return rootIds;
    }

    Map<Id, Product2> relationshipProductsById = loadRelationshipProducts(
      changedProductIds,
      hasProductGroupRoots
    );
    for (Id changedProductId : changedProductIds) {
      rootIds.add(
        resolveRootProductId(
          changedProductId,
          relationshipProductsById,
          hasProductGroupRoots
        )
      );
    }
    return rootIds;
  }

  private static Map<Id, Product2> loadRelationshipProducts(
    Set<Id> seedProductIds,
    Boolean includeGroupField
  ) {
    Map<Id, Product2> productsById = new Map<Id, Product2>();
    Set<Id> frontier = new Set<Id>(seedProductIds);

    Integer guard = 0;
    while (!frontier.isEmpty() && guard++ < MAX_HIERARCHY_DEPTH) {
      Set<Id> nextFrontier = new Set<Id>();
      for (Product2 product : queryRelationshipProducts(frontier, includeGroupField)) {
        productsById.put(product.Id, product);

        Id productGroupId;
        if (includeGroupField) {
          productGroupId = SafeFieldUtil.safeGetId(
            product,
            'Product_Group__c'
          );
          if (
            productGroupId != null &&
            !productsById.containsKey(productGroupId)
          ) {
            nextFrontier.add(productGroupId);
          }
        }

        // GroupingWithVariants resolves a configured Product Group before its
        // parent chain. Follow only the relationship that can become the root
        // so each level contains no more records than the bounded seed scope.
        if (productGroupId == null) {
          Id parentProductId = SafeFieldUtil.safeGetId(
            product,
            'Parent_Product__c'
          );
          if (
            parentProductId != null &&
            !productsById.containsKey(parentProductId)
          ) {
            nextFrontier.add(parentProductId);
          }
        }
      }
      frontier = nextFrontier;
    }
    return productsById;
  }

  private static List<Product2> queryRelationshipProducts(
    Set<Id> productIds,
    Boolean includeGroupField
  ) {
    if (productIds == null || productIds.isEmpty()) {
      return new List<Product2>();
    }

    List<String> fields = new List<String>{ 'Id' };
    addProductFieldIfPresent(fields, 'Parent_Product__c');
    addProductFieldIfPresent(fields, 'Type');
    if (includeGroupField) {
      addProductFieldIfPresent(fields, 'Product_Group__c');
    }
    return Database.query(
      'SELECT ' +
        String.join(fields, ', ') +
        ' FROM Product2 WHERE Id IN :productIds'
    );
  }

  private static Id resolveRootProductId(
    Id productId,
    Map<Id, Product2> productsById,
    Boolean useProductGroupRoots
  ) {
    Id currentProductId = productId;
    Integer guard = 0;
    while (currentProductId != null && guard++ < MAX_HIERARCHY_DEPTH) {
      Product2 currentProduct = productsById.get(currentProductId);
      if (currentProduct == null) {
        return currentProductId;
      }

      if (useProductGroupRoots) {
        Id productGroupId = SafeFieldUtil.safeGetId(
          currentProduct,
          'Product_Group__c'
        );
        if (productGroupId != null) {
          return productGroupId;
        }
      }

      Id parentProductId = SafeFieldUtil.safeGetId(
        currentProduct,
        'Parent_Product__c'
      );
      if (parentProductId == null) {
        return currentProductId;
      }
      currentProductId = parentProductId;
    }
    return currentProductId == null ? productId : currentProductId;
  }

  private static void addProductFieldIfPresent(
    List<String> fields,
    String fieldName
  ) {
    if (PRODUCT_FIELDS.containsKey(fieldName) && !fields.contains(fieldName)) {
      fields.add(fieldName);
    }
  }
}
