public with sharing class CatalogJobScopeUtil {
  public static Database.QueryLocator buildProductQueryLocator(
    CatalogJobConfig__mdt jobConfig,
    List<String> requiredFieldNames,
    List<String> extraFieldNames
  ) {
    return buildProductQueryLocatorForIds(
      jobConfig,
      null,
      requiredFieldNames,
      extraFieldNames
    );
  }

  public static Database.QueryLocator buildProductQueryLocatorForIds(
    CatalogJobConfig__mdt jobConfig,
    Set<Id> productIds,
    List<String> requiredFieldNames,
    List<String> extraFieldNames
  ) {
    return Database.getQueryLocator(
      buildScopedProductQuery(
        jobConfig,
        productIds,
        requiredFieldNames,
        extraFieldNames
      )
    );
  }

  public static List<Product2> queryProductsByIds(
    CatalogJobConfig__mdt jobConfig,
    Set<Id> productIds,
    List<String> requiredFieldNames
  ) {
    return queryProductsByIds(jobConfig, productIds, requiredFieldNames, null);
  }

  public static List<Product2> queryProductsByIds(
    CatalogJobConfig__mdt jobConfig,
    Set<Id> productIds,
    List<String> requiredFieldNames,
    List<String> extraFieldNames
  ) {
    if (productIds == null || productIds.isEmpty()) {
      return new List<Product2>();
    }

    return Database.query(
      buildScopedProductQuery(
        jobConfig,
        productIds,
        requiredFieldNames,
        extraFieldNames
      )
    );
  }

  public static String getExportedItemId(Product2 product) {
    return CatalogProductIdentityResolver.resolveFallbackEcProductId(product);
  }

  private static List<String> buildFieldList(
    List<String> requiredFieldNames,
    List<String> extraFieldNames
  ) {
    List<String> fields = new List<String>();

    if (requiredFieldNames != null) {
      for (String fieldName : requiredFieldNames) {
        addFieldIfMissing(fields, fieldName);
      }
    }

    if (extraFieldNames != null) {
      for (String fieldName : extraFieldNames) {
        addFieldIfMissing(fields, fieldName);
      }
    }

    return fields;
  }

  private static String buildScopedProductQuery(
    CatalogJobConfig__mdt jobConfig,
    Set<Id> productIds,
    List<String> requiredFieldNames,
    List<String> extraFieldNames
  ) {
    List<String> fields = buildFieldList(requiredFieldNames, extraFieldNames);
    if (!fields.contains('Id')) {
      fields.add('Id');
    }

    String query =
      'SELECT ' +
      String.join(fields, ', ') +
      ' FROM Product2 WHERE IsActive = true';

    if (productIds != null) {
      if (productIds.isEmpty()) {
        return 'SELECT Id FROM Product2 WHERE Id = null';
      }
      query += ' AND Id IN :productIds';
    }

    if (!String.isBlank(jobConfig.CatalogId__c)) {
      query +=
        ' AND Id IN (SELECT ProductId FROM ProductCategoryProduct WHERE ProductCategory.CatalogId = \'' +
        String.escapeSingleQuotes(jobConfig.CatalogId__c) +
        '\' AND ProductId != NULL)';
    }

    if (!String.isBlank(jobConfig.ProductFilter__c)) {
      String sanitizedFilter = validateAndSanitizeFilter(
        jobConfig.ProductFilter__c
      );
      query += ' AND (' + sanitizedFilter + ')';
    }

    return query;
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

  @TestVisible
  private static Set<Id> getProductIdsForCatalog(String catalogId) {
    Set<Id> productIds = new Set<Id>();

    for (ProductCategoryProduct pcp : [
      SELECT ProductId
      FROM ProductCategoryProduct
      WHERE ProductCategory.CatalogId = :catalogId AND ProductId != NULL
    ]) {
      productIds.add(pcp.ProductId);
    }

    return productIds;
  }

  @TestVisible
  private static String validateAndSanitizeFilter(String filter) {
    if (String.isBlank(filter)) {
      return filter;
    }

    String trimmedFilter = filter.trim();
    String normalizedFilter = trimmedFilter.replaceAll('[\\t\\n\\r]+', ' ')
      .toUpperCase();

    List<String> dmlPatterns = new List<String>{
      'INSERT ',
      'UPDATE ',
      'DELETE ',
      'UPSERT ',
      'MERGE ',
      'UNDELETE '
    };

    for (String pattern : dmlPatterns) {
      if (normalizedFilter.contains(pattern)) {
        throw new CatalogJobException(
          'Invalid ProductFilter__c value: contains DML keyword "' +
            pattern.trim() +
            '". Only valid SOQL WHERE clause fragments are allowed.'
        );
      }
    }

    if (
      normalizedFilter.contains('SELECT ') &&
      normalizedFilter.contains(' FROM ')
    ) {
      throw new CatalogJobException(
        'Invalid ProductFilter__c value: contains subquery pattern. ' +
        'Only simple SOQL WHERE clause fragments are allowed.'
      );
    }

    return trimmedFilter;
  }
}
