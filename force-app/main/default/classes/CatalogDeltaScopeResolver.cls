public with sharing class CatalogDeltaScopeResolver {
  private static final Integer MAX_HIERARCHY_DEPTH = 20;
  private static final Map<String, SObjectField> PRODUCT_FIELDS = Product2.SObjectType
    .getDescribe()
    .fields.getMap();

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
    return computeScope(jobConfig, lowerExclusive, upperInclusive).exportProductIds;
  }

  public static ScopeMetrics describeScope(
    CatalogJobConfig__mdt jobConfig,
    Datetime lowerExclusive,
    Datetime upperInclusive
  ) {
    ScopeComputation computation = computeScope(
      jobConfig,
      lowerExclusive,
      upperInclusive
    );

    ScopeMetrics metrics = new ScopeMetrics();
    metrics.impactedProductCount = computation.changedProductIds.size();
    metrics.rootProductCount = computation.rootProductIds.size();
    metrics.exportProductCount = computation.exportProductIds.size();
    return metrics;
  }

  @TestVisible
  private class ScopeComputation {
    public Set<Id> changedProductIds = new Set<Id>();
    public Set<Id> rootProductIds = new Set<Id>();
    public Set<Id> exportProductIds = new Set<Id>();
  }

  @TestVisible
  private static ScopeComputation computeScope(
    CatalogJobConfig__mdt jobConfig,
    Datetime lowerExclusive,
    Datetime upperInclusive
  ) {
    ScopeComputation computation = new ScopeComputation();

    if (
      jobConfig == null ||
      lowerExclusive == null ||
      upperInclusive == null ||
      lowerExclusive.getTime() >= upperInclusive.getTime()
    ) {
      return computation;
    }

    computation.changedProductIds = collectChangedProductIds(
      jobConfig,
      lowerExclusive,
      upperInclusive
    );
    if (computation.changedProductIds.isEmpty()) {
      return computation;
    }

    computation.rootProductIds = resolveRootProductIds(
      jobConfig,
      computation.changedProductIds
    );
    if (computation.rootProductIds.isEmpty()) {
      return computation;
    }

    Set<Id> expandedProductIds = expandExportProductIds(
      jobConfig,
      computation.rootProductIds
    );
    if (expandedProductIds.isEmpty()) {
      return computation;
    }

    computation.exportProductIds = new Set<Id>();
    for (
      Product2 product : CatalogJobScopeUtil.queryProductsByIds(
        jobConfig,
        expandedProductIds,
        new List<String>{ 'Id' }
      )
    ) {
      computation.exportProductIds.add(product.Id);
    }

    return computation;
  }

  @TestVisible
  private static Set<Id> collectChangedProductIds(
    CatalogJobConfig__mdt jobConfig,
    Datetime lowerExclusive,
    Datetime upperInclusive
  ) {
    Set<Id> changedProductIds = new Set<Id>();

    for (Product2 product : [
      SELECT Id
      FROM Product2
      WHERE SystemModstamp > :lowerExclusive AND SystemModstamp <= :upperInclusive
    ]) {
      changedProductIds.add(product.Id);
    }

    for (PricebookEntry pricebookEntry : [
      SELECT Product2Id
      FROM PricebookEntry
      WHERE Product2Id != NULL
      AND SystemModstamp > :lowerExclusive
      AND SystemModstamp <= :upperInclusive
    ]) {
      changedProductIds.add(pricebookEntry.Product2Id);
    }

    for (ProductCategoryProduct categoryProduct : [
      SELECT ProductId
      FROM ProductCategoryProduct
      WHERE ProductId != NULL
      AND SystemModstamp > :lowerExclusive
      AND SystemModstamp <= :upperInclusive
    ]) {
      changedProductIds.add(categoryProduct.ProductId);
    }

    Set<Id> impactedCategoryIds = collectImpactedCategoryIds(
      jobConfig,
      lowerExclusive,
      upperInclusive
    );
    if (!impactedCategoryIds.isEmpty()) {
      for (ProductCategoryProduct categoryProduct : [
        SELECT ProductId
        FROM ProductCategoryProduct
        WHERE ProductId != NULL AND ProductCategoryId IN :impactedCategoryIds
      ]) {
        changedProductIds.add(categoryProduct.ProductId);
      }
    }

    return changedProductIds;
  }

  @TestVisible
  private static Set<Id> collectImpactedCategoryIds(
    CatalogJobConfig__mdt jobConfig,
    Datetime lowerExclusive,
    Datetime upperInclusive
  ) {
    Set<Id> changedCategoryIds = new Set<Id>();
    String catalogId = jobConfig == null ? null : jobConfig.CatalogId__c;

    if (String.isBlank(catalogId)) {
      for (ProductCategory category : [
        SELECT Id
        FROM ProductCategory
        WHERE SystemModstamp > :lowerExclusive AND SystemModstamp <= :upperInclusive
      ]) {
        changedCategoryIds.add(category.Id);
      }
    } else {
      for (ProductCategory category : [
        SELECT Id
        FROM ProductCategory
        WHERE CatalogId = :catalogId
        AND SystemModstamp > :lowerExclusive
        AND SystemModstamp <= :upperInclusive
      ]) {
        changedCategoryIds.add(category.Id);
      }
    }

    if (changedCategoryIds.isEmpty()) {
      return changedCategoryIds;
    }

    Set<Id> impactedCategoryIds = new Set<Id>();
    impactedCategoryIds.addAll(changedCategoryIds);

    Set<Id> frontier = new Set<Id>();
    frontier.addAll(changedCategoryIds);

    Integer guard = 0;
    while (!frontier.isEmpty() && guard++ < MAX_HIERARCHY_DEPTH) {
      Set<Id> childIds = new Set<Id>();

      if (String.isBlank(catalogId)) {
        for (ProductCategory category : [
          SELECT Id
          FROM ProductCategory
          WHERE ParentCategoryId IN :frontier
        ]) {
          if (impactedCategoryIds.add(category.Id)) {
            childIds.add(category.Id);
          }
        }
      } else {
        for (ProductCategory category : [
          SELECT Id
          FROM ProductCategory
          WHERE CatalogId = :catalogId AND ParentCategoryId IN :frontier
        ]) {
          if (impactedCategoryIds.add(category.Id)) {
            childIds.add(category.Id);
          }
        }
      }

      frontier = childIds;
    }

    return impactedCategoryIds;
  }

  @TestVisible
  private static Set<Id> resolveRootProductIds(
    CatalogJobConfig__mdt jobConfig,
    Set<Id> changedProductIds
  ) {
    Set<Id> rootIds = new Set<Id>();

    if (changedProductIds == null || changedProductIds.isEmpty()) {
      return rootIds;
    }

    ICatalogJsonBuilder builder = CatalogProductIdentityResolver.getBuilder(
      jobConfig
    );
    Boolean usesParentHierarchy =
      builder instanceof CatalogJsonBuilderGrouping ||
      builder instanceof CatalogJsonBuilderVariant ||
      builder instanceof CatalogJsonBuilderGroupingWithVariants;
    Boolean usesProductGroupRoots =
      builder instanceof CatalogJsonBuilderGroupingWithVariants;

    if (!usesParentHierarchy && !usesProductGroupRoots) {
      rootIds.addAll(changedProductIds);
      return rootIds;
    }

    Map<Id, Product2> relationshipProductsById = loadRelationshipProducts(
      changedProductIds,
      usesProductGroupRoots
    );

    for (Id changedProductId : changedProductIds) {
      rootIds.add(
        resolveRootProductId(
          changedProductId,
          relationshipProductsById,
          usesProductGroupRoots
        )
      );
    }

    return rootIds;
  }

  @TestVisible
  private static Set<Id> expandExportProductIds(
    CatalogJobConfig__mdt jobConfig,
    Set<Id> rootProductIds
  ) {
    Set<Id> expandedProductIds = new Set<Id>();

    if (rootProductIds == null || rootProductIds.isEmpty()) {
      return expandedProductIds;
    }

    expandedProductIds.addAll(rootProductIds);

    ICatalogJsonBuilder builder = CatalogProductIdentityResolver.getBuilder(
      jobConfig
    );
    if (builder instanceof CatalogJsonBuilderGroupingWithVariants) {
      expandedProductIds.addAll(loadProductsByGroup(rootProductIds));
      expandedProductIds.addAll(loadProductsByParent(expandedProductIds));
      return expandedProductIds;
    }

    if (
      builder instanceof CatalogJsonBuilderGrouping ||
      builder instanceof CatalogJsonBuilderVariant
    ) {
      expandedProductIds.addAll(loadProductsByParent(rootProductIds));
    }

    return expandedProductIds;
  }

  private static Map<Id, Product2> loadRelationshipProducts(
    Set<Id> seedProductIds,
    Boolean includeGroupField
  ) {
    Map<Id, Product2> productsById = new Map<Id, Product2>();
    Set<Id> frontier = new Set<Id>();
    frontier.addAll(seedProductIds);

    Integer guard = 0;
    while (!frontier.isEmpty() && guard++ < MAX_HIERARCHY_DEPTH) {
      Set<Id> nextFrontier = new Set<Id>();

      for (Product2 product : queryRelationshipProducts(frontier, includeGroupField)) {
        productsById.put(product.Id, product);

        Id parentProductId = SafeFieldUtil.safeGetId(product, 'Parent_Product__c');
        if (
          parentProductId != null &&
          !productsById.containsKey(parentProductId)
        ) {
          nextFrontier.add(parentProductId);
        }

        if (includeGroupField) {
          Id productGroupId = SafeFieldUtil.safeGetId(product, 'Product_Group__c');
          if (
            productGroupId != null &&
            !productsById.containsKey(productGroupId)
          ) {
            nextFrontier.add(productGroupId);
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

  private static Set<Id> loadProductsByParent(Set<Id> parentProductIds) {
    Set<Id> expandedProductIds = new Set<Id>();

    if (
      parentProductIds == null ||
      parentProductIds.isEmpty() ||
      !PRODUCT_FIELDS.containsKey('Parent_Product__c')
    ) {
      return expandedProductIds;
    }

    Set<Id> frontier = new Set<Id>();
    frontier.addAll(parentProductIds);

    Integer guard = 0;
    while (!frontier.isEmpty() && guard++ < MAX_HIERARCHY_DEPTH) {
      Set<Id> childIds = new Set<Id>();
      for (Product2 childProduct : [
        SELECT Id
        FROM Product2
        WHERE Parent_Product__c IN :frontier
      ]) {
        if (expandedProductIds.add(childProduct.Id)) {
          childIds.add(childProduct.Id);
        }
      }

      frontier = childIds;
    }

    return expandedProductIds;
  }

  private static Set<Id> loadProductsByGroup(Set<Id> groupProductIds) {
    Set<Id> groupedProductIds = new Set<Id>();

    if (
      groupProductIds == null ||
      groupProductIds.isEmpty() ||
      !PRODUCT_FIELDS.containsKey('Product_Group__c')
    ) {
      return groupedProductIds;
    }

    for (Product2 groupedProduct : [
      SELECT Id
      FROM Product2
      WHERE Product_Group__c IN :groupProductIds
    ]) {
      groupedProductIds.add(groupedProduct.Id);
    }

    return groupedProductIds;
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
