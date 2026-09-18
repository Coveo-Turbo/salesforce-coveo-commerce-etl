global with sharing class CatalogDeltaStageBatch implements Database.Batchable<SObject>, Database.Stateful {
  public static final String DISCOVER_PRODUCTS = 'DISCOVER_PRODUCTS';
  public static final String DISCOVER_PRICES = 'DISCOVER_PRICES';
  public static final String DISCOVER_ASSIGNMENTS = 'DISCOVER_ASSIGNMENTS';
  public static final String DISCOVER_CATEGORIES = 'DISCOVER_CATEGORIES';
  public static final String EXPAND_CATEGORIES = 'EXPAND_CATEGORIES';
  public static final String FAN_OUT_CATEGORY_PRODUCTS = 'FAN_OUT_CATEGORY_PRODUCTS';
  public static final String RESOLVE_ROOTS = 'RESOLVE_ROOTS';
  public static final String EXPAND_GROUP_MEMBERS = 'EXPAND_GROUP_MEMBERS';
  public static final String EXPAND_CHILDREN = 'EXPAND_CHILDREN';
  public static final String EXPORT_PRODUCTS = 'EXPORT_PRODUCTS';

  @TestVisible
  private static final Integer MAX_HIERARCHY_DEPTH = 20;
  private static final String PRODUCT_KIND = 'Product';
  private static final String CATEGORY_KIND = 'Category';
  private static final Map<String, SObjectField> PRODUCT_FIELDS = Product2.SObjectType
    .getDescribe()
    .fields.getMap();

  private final Id runId;
  private final String stage;
  private final Integer traversalDepth;
  private final CatalogJobConfig__mdt jobConfig;
  private Integer newTraversalItems = 0;
  private Integer newImpactedItems = 0;
  private Integer newRootItems = 0;

  global CatalogDeltaStageBatch(
    Id runId,
    String stage,
    Integer traversalDepth,
    CatalogJobConfig__mdt jobConfig
  ) {
    if (runId == null || String.isBlank(stage) || jobConfig == null) {
      throw new CatalogJobException(
        'Delta run, stage, and catalog configuration are required.'
      );
    }
    this.runId = runId;
    this.stage = stage;
    this.traversalDepth = traversalDepth == null ? 0 : traversalDepth;
    this.jobConfig = jobConfig;
  }

  global Database.QueryLocator start(Database.BatchableContext context) {
    Catalog_Delta_Run__c run = CatalogDeltaRunService.loadRun(runId);
    if (
      run.Status__c == CatalogDeltaRunService.STATUS_CANCEL_REQUESTED ||
      run.Status__c == CatalogDeltaRunService.STATUS_CANCELED
    ) {
      return emptyLocator();
    }
    if (CatalogDeltaRunService.isTerminalStatus(run.Status__c)) {
      return emptyLocator();
    }
    if (run.Stage__c != stage) {
      throw new CatalogJobException(
        'Delta run stage mismatch. Expected ' + run.Stage__c + ' but received ' + stage + '.'
      );
    }
    return buildStageLocator(run);
  }

  global void execute(Database.BatchableContext context, List<SObject> scope) {
    if (scope == null || scope.isEmpty()) {
      return;
    }

    if (stage == DISCOVER_PRODUCTS) {
      stageProducts(productIds(scope, 'Id'), true, false, false, null);
      return;
    }
    if (stage == DISCOVER_PRICES) {
      stageProducts(productIds(scope, 'Product2Id'), true, false, false, null);
      return;
    }
    if (
      stage == DISCOVER_ASSIGNMENTS || stage == FAN_OUT_CATEGORY_PRODUCTS
    ) {
      stageProducts(productIds(scope, 'ProductId'), true, false, false, null);
      return;
    }
    if (stage == DISCOVER_CATEGORIES || stage == EXPAND_CATEGORIES) {
      stageCategories(recordIds(scope), traversalDepth + (stage == EXPAND_CATEGORIES ? 1 : 0));
      return;
    }
    if (stage == RESOLVE_ROOTS) {
      Set<Id> impactedProductIds = productIds(scope, 'Product__c');
      Set<Id> rootProductIds = CatalogDeltaScopeResolver.resolveRootProductIds(
        jobConfig,
        impactedProductIds
      );
      stageProducts(rootProductIds, false, true, true, 0);
      return;
    }
    if (stage == EXPAND_GROUP_MEMBERS || stage == EXPAND_CHILDREN) {
      stageProducts(
        recordIds(scope),
        false,
        false,
        true,
        stage == EXPAND_GROUP_MEMBERS ? 0 : traversalDepth + 1
      );
      return;
    }

    throw new CatalogJobException('Unsupported delta pipeline stage: ' + stage);
  }

  global void finish(Database.BatchableContext context) {
    if (!batchCompletedWithoutErrors(context)) {
      CatalogDeltaRunService.failRun(
        runId,
        'Delta pipeline stage ' + stage + ' failed. Review the Async Apex job for details.'
      );
      return;
    }

    Catalog_Delta_Run__c run = CatalogDeltaRunService.loadRun(runId);
    if (
      run.Status__c == CatalogDeltaRunService.STATUS_CANCEL_REQUESTED ||
      run.Status__c == CatalogDeltaRunService.STATUS_CANCELED
    ) {
      CatalogDeltaRunService.failRun(runId, 'Delta pipeline was canceled.');
      return;
    }
    if (CatalogDeltaRunService.isTerminalStatus(run.Status__c)) {
      return;
    }

    CatalogDeltaRunService.applyMetricDeltas(
      runId,
      newImpactedItems,
      newRootItems
    );
    launchNextStage();
  }

  @TestVisible
  private void launchNextStage() {
    if (stage == DISCOVER_PRODUCTS) {
      nextStage(DISCOVER_PRICES, 0);
      return;
    }
    if (stage == DISCOVER_PRICES) {
      nextStage(DISCOVER_ASSIGNMENTS, 0);
      return;
    }
    if (stage == DISCOVER_ASSIGNMENTS) {
      nextStage(DISCOVER_CATEGORIES, 0);
      return;
    }
    if (stage == DISCOVER_CATEGORIES) {
      nextStage(EXPAND_CATEGORIES, 0);
      return;
    }
    if (stage == EXPAND_CATEGORIES) {
      if (newTraversalItems > 0) {
        if (traversalDepth >= MAX_HIERARCHY_DEPTH) {
          CatalogDeltaRunService.failRun(
            runId,
            'Product category hierarchy exceeds the supported depth of ' +
              MAX_HIERARCHY_DEPTH +
              '.'
          );
          return;
        }
        nextStage(EXPAND_CATEGORIES, traversalDepth + 1);
      } else {
        nextStage(FAN_OUT_CATEGORY_PRODUCTS, 0);
      }
      return;
    }
    if (stage == FAN_OUT_CATEGORY_PRODUCTS) {
      nextStage(RESOLVE_ROOTS, 0);
      return;
    }
    if (stage == RESOLVE_ROOTS) {
      if (CatalogDeltaScopeResolver.usesProductGroupRoots(jobConfig)) {
        nextStage(EXPAND_GROUP_MEMBERS, 0);
      } else if (CatalogDeltaScopeResolver.usesParentHierarchy(jobConfig)) {
        nextStage(EXPAND_CHILDREN, 0);
      } else {
        CatalogDeltaRunService.enqueueExport(runId, jobConfig);
      }
      return;
    }
    if (stage == EXPAND_GROUP_MEMBERS) {
      nextStage(EXPAND_CHILDREN, 0);
      return;
    }
    if (stage == EXPAND_CHILDREN) {
      if (newTraversalItems > 0) {
        if (traversalDepth >= MAX_HIERARCHY_DEPTH) {
          CatalogDeltaRunService.failRun(
            runId,
            'Product family hierarchy exceeds the supported depth of ' +
              MAX_HIERARCHY_DEPTH +
              '.'
          );
          return;
        }
        nextStage(EXPAND_CHILDREN, traversalDepth + 1);
      } else {
        CatalogDeltaRunService.enqueueExport(runId, jobConfig);
      }
      return;
    }
    throw new CatalogJobException('Unsupported completed delta stage: ' + stage);
  }

  private void nextStage(String nextStageName, Integer nextDepth) {
    CatalogDeltaRunService.enqueueStage(
      runId,
      nextStageName,
      nextDepth,
      jobConfig
    );
  }

  private Database.QueryLocator buildStageLocator(Catalog_Delta_Run__c run) {
    Datetime baselineTimestamp = run.BaselineTimestamp__c;
    Datetime cutoffTimestamp = run.CutoffTimestamp__c;
    String catalogId = jobConfig.CatalogId__c;
    Id currentRunId = runId;
    Decimal frontierDepth = traversalDepth;

    if (stage == DISCOVER_PRODUCTS) {
      String query =
        'SELECT Id FROM Product2 WHERE SystemModstamp > :baselineTimestamp ' +
        'AND SystemModstamp <= :cutoffTimestamp';
      if (!CatalogDeltaScopeResolver.usesParentHierarchy(jobConfig)) {
        query += ' AND IsActive = TRUE';
        query += buildCatalogProductPredicate(catalogId);
        if (String.isNotBlank(jobConfig.ProductFilter__c)) {
          query +=
            ' AND (' +
            CatalogJobScopeUtil.validateAndSanitizeFilter(
              jobConfig.ProductFilter__c
            ) +
            ')';
        }
      }
      return Database.getQueryLocator(query);
    }

    if (stage == DISCOVER_PRICES) {
      String query =
        'SELECT Product2Id FROM PricebookEntry WHERE Product2Id != NULL ' +
        'AND SystemModstamp > :baselineTimestamp AND SystemModstamp <= :cutoffTimestamp';
      Set<Id> pricebookIds = CatalogDeltaRunService.getResolvedPricebookIds(run);
      if (pricebookIds != null) {
        if (String.isNotBlank(run.StandardPricebookId__c)) {
          pricebookIds.add((Id) run.StandardPricebookId__c);
        }
        if (pricebookIds.isEmpty()) {
          return Database.getQueryLocator(
            'SELECT Product2Id FROM PricebookEntry WHERE Id = NULL'
          );
        }
        query += ' AND Pricebook2Id IN :pricebookIds';
      }
      if (
        !CatalogDeltaScopeResolver.usesParentHierarchy(jobConfig) &&
        String.isNotBlank(catalogId)
      ) {
        query +=
          ' AND Product2Id IN (SELECT ProductId FROM ProductCategoryProduct ' +
          'WHERE ProductCategory.CatalogId = :catalogId AND ProductId != NULL)';
      }
      return Database.getQueryLocator(query);
    }

    if (stage == DISCOVER_ASSIGNMENTS) {
      String query =
        'SELECT ProductId FROM ProductCategoryProduct WHERE ProductId != NULL ' +
        'AND SystemModstamp > :baselineTimestamp AND SystemModstamp <= :cutoffTimestamp';
      if (String.isNotBlank(catalogId)) {
        query += ' AND ProductCategory.CatalogId = :catalogId';
      }
      return Database.getQueryLocator(query);
    }

    if (stage == DISCOVER_CATEGORIES) {
      String query =
        'SELECT Id FROM ProductCategory WHERE SystemModstamp > :baselineTimestamp ' +
        'AND SystemModstamp <= :cutoffTimestamp';
      if (String.isNotBlank(catalogId)) {
        query += ' AND CatalogId = :catalogId';
      }
      return Database.getQueryLocator(query);
    }

    if (stage == EXPAND_CATEGORIES) {
      String query =
        'SELECT Id FROM ProductCategory WHERE ParentCategoryId IN (' +
        'SELECT ProductCategory__c FROM Catalog_Delta_Work_Item__c ' +
        'WHERE Run__c = :currentRunId AND Kind__c = \'Category\' ' +
        'AND TraversalDepth__c = :frontierDepth)';
      if (String.isNotBlank(catalogId)) {
        query += ' AND CatalogId = :catalogId';
      }
      return Database.getQueryLocator(query);
    }

    if (stage == FAN_OUT_CATEGORY_PRODUCTS) {
      return Database.getQueryLocator(
        'SELECT ProductId FROM ProductCategoryProduct WHERE ProductId != NULL ' +
        'AND ProductCategoryId IN (SELECT ProductCategory__c ' +
        'FROM Catalog_Delta_Work_Item__c WHERE Run__c = :currentRunId ' +
        'AND Kind__c = \'Category\')'
      );
    }

    if (stage == RESOLVE_ROOTS) {
      return Database.getQueryLocator(
        'SELECT Product__c FROM Catalog_Delta_Work_Item__c ' +
        'WHERE Run__c = :currentRunId AND Kind__c = \'Product\' ' +
        'AND IsImpacted__c = TRUE AND Product__c != NULL'
      );
    }

    if (stage == EXPAND_GROUP_MEMBERS) {
      if (!PRODUCT_FIELDS.containsKey('Product_Group__c')) {
        return emptyLocator();
      }
      return Database.getQueryLocator(
        'SELECT Id FROM Product2 WHERE Product_Group__c IN (' +
        'SELECT Product__c FROM Catalog_Delta_Work_Item__c ' +
        'WHERE Run__c = :currentRunId AND Kind__c = \'Product\' ' +
        'AND IsRoot__c = TRUE AND Product__c != NULL)'
      );
    }

    if (stage == EXPAND_CHILDREN) {
      if (!PRODUCT_FIELDS.containsKey('Parent_Product__c')) {
        return emptyLocator();
      }
      return Database.getQueryLocator(
        'SELECT Id FROM Product2 WHERE Parent_Product__c IN (' +
        'SELECT Product__c FROM Catalog_Delta_Work_Item__c ' +
        'WHERE Run__c = :currentRunId AND Kind__c = \'Product\' ' +
        'AND IsExportCandidate__c = TRUE AND TraversalDepth__c = :frontierDepth ' +
        'AND Product__c != NULL)'
      );
    }

    throw new CatalogJobException('Unsupported delta pipeline stage: ' + stage);
  }

  @TestVisible
  private static String buildCatalogProductPredicate(String catalogId) {
    if (String.isBlank(catalogId)) {
      return '';
    }
    return (
      ' AND Id IN (SELECT ProductId FROM ProductCategoryProduct ' +
      'WHERE ProductCategory.CatalogId = :catalogId AND ProductId != NULL)'
    );
  }

  private void stageProducts(
    Set<Id> productIds,
    Boolean markImpacted,
    Boolean markRoot,
    Boolean markExportCandidate,
    Integer depth
  ) {
    if (productIds == null || productIds.isEmpty()) {
      return;
    }

    Map<Id, Catalog_Delta_Work_Item__c> existingByProductId = new Map<Id, Catalog_Delta_Work_Item__c>();
    for (Catalog_Delta_Work_Item__c item : [
      SELECT
        Id,
        Product__c,
        IsImpacted__c,
        IsRoot__c,
        IsExportCandidate__c,
        TraversalDepth__c
      FROM Catalog_Delta_Work_Item__c
      WHERE Run__c = :runId AND Kind__c = :PRODUCT_KIND AND Product__c IN :productIds
    ]) {
      existingByProductId.put(item.Product__c, item);
    }

    List<Catalog_Delta_Work_Item__c> inserts = new List<Catalog_Delta_Work_Item__c>();
    List<Catalog_Delta_Work_Item__c> updates = new List<Catalog_Delta_Work_Item__c>();
    for (Id productId : productIds) {
      Catalog_Delta_Work_Item__c item = existingByProductId.get(productId);
      Boolean isNew = item == null;
      if (isNew) {
        item = new Catalog_Delta_Work_Item__c(
          Run__c = runId,
          DedupeKey__c = buildDedupeKey(PRODUCT_KIND, productId),
          Kind__c = PRODUCT_KIND,
          Product__c = productId
        );
      }

      Boolean changed = isNew;
      if (markImpacted && item.IsImpacted__c != true) {
        item.IsImpacted__c = true;
        newImpactedItems++;
        changed = true;
      }
      if (markRoot && item.IsRoot__c != true) {
        item.IsRoot__c = true;
        newRootItems++;
        changed = true;
      }
      if (markExportCandidate && item.IsExportCandidate__c != true) {
        item.IsExportCandidate__c = true;
        item.TraversalDepth__c = depth;
        newTraversalItems++;
        changed = true;
      }

      if (isNew) {
        inserts.add(item);
      } else if (changed) {
        updates.add(item);
      }
    }
    if (!inserts.isEmpty()) {
      insert inserts;
    }
    if (!updates.isEmpty()) {
      update updates;
    }
  }

  private void stageCategories(Set<Id> categoryIds, Integer depth) {
    if (categoryIds == null || categoryIds.isEmpty()) {
      return;
    }
    Set<Id> existingCategoryIds = new Set<Id>();
    for (Catalog_Delta_Work_Item__c item : [
      SELECT ProductCategory__c
      FROM Catalog_Delta_Work_Item__c
      WHERE
        Run__c = :runId
        AND Kind__c = :CATEGORY_KIND
        AND ProductCategory__c IN :categoryIds
    ]) {
      existingCategoryIds.add(item.ProductCategory__c);
    }

    List<Catalog_Delta_Work_Item__c> inserts = new List<Catalog_Delta_Work_Item__c>();
    for (Id categoryId : categoryIds) {
      if (existingCategoryIds.contains(categoryId)) {
        continue;
      }
      inserts.add(
        new Catalog_Delta_Work_Item__c(
          Run__c = runId,
          DedupeKey__c = buildDedupeKey(CATEGORY_KIND, categoryId),
          Kind__c = CATEGORY_KIND,
          ProductCategory__c = categoryId,
          TraversalDepth__c = depth
        )
      );
      newTraversalItems++;
    }
    if (!inserts.isEmpty()) {
      insert inserts;
    }
  }

  private String buildDedupeKey(String kind, Id recordId) {
    return String.valueOf(runId) +
      '|' +
      (kind == PRODUCT_KIND ? 'P' : 'C') +
      '|' +
      String.valueOf(recordId);
  }

  private static Set<Id> recordIds(List<SObject> scope) {
    return productIds(scope, 'Id');
  }

  private static Set<Id> productIds(List<SObject> scope, String fieldName) {
    Set<Id> ids = new Set<Id>();
    for (SObject record : scope) {
      Id recordId = (Id) record.get(fieldName);
      if (recordId != null) {
        ids.add(recordId);
      }
    }
    return ids;
  }

  private static Database.QueryLocator emptyLocator() {
    return Database.getQueryLocator('SELECT Id FROM Product2 WHERE Id = NULL');
  }

  @TestVisible
  private static Boolean batchCompletedWithoutErrors(
    Database.BatchableContext context
  ) {
    if (context == null) {
      return true;
    }
    List<AsyncApexJob> jobs = [
      SELECT Status, NumberOfErrors
      FROM AsyncApexJob
      WHERE Id = :context.getJobId()
      LIMIT 1
    ];
    return !jobs.isEmpty() &&
      jobs[0].NumberOfErrors == 0 &&
      jobs[0].Status != 'Failed' &&
      jobs[0].Status != 'Aborted';
  }
}
