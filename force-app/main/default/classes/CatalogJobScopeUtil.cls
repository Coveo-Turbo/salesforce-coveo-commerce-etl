public with sharing class CatalogJobScopeUtil {
  public static Database.QueryLocator buildProductQueryLocator(
    CatalogJobConfig__mdt jobConfig,
    List<String> requiredFieldNames,
    List<String> extraFieldNames
  ) {
    List<String> fields = buildFieldList(requiredFieldNames, extraFieldNames);

    String query =
      'SELECT ' +
      String.join(fields, ', ') +
      ' FROM Product2 WHERE IsActive = true';

    if (!String.isBlank(jobConfig.CatalogId__c)) {
      Set<Id> productIdsInCatalog = getProductIdsForCatalog(
        jobConfig.CatalogId__c
      );
      if (productIdsInCatalog.isEmpty()) {
        return Database.getQueryLocator(
          'SELECT Id FROM Product2 WHERE Id = null'
        );
      }
      query += ' AND Id IN :productIdsInCatalog';
    }

    if (!String.isBlank(jobConfig.ProductFilter__c)) {
      String sanitizedFilter = validateAndSanitizeFilter(
        jobConfig.ProductFilter__c
      );
      query += ' AND (' + sanitizedFilter + ')';
    }

    return Database.getQueryLocator(query);
  }

  public static List<Product2> queryProductsByIds(
    CatalogJobConfig__mdt jobConfig,
    Set<Id> productIds,
    List<String> requiredFieldNames
  ) {
    if (productIds == null || productIds.isEmpty()) {
      return new List<Product2>();
    }

    List<String> fields = buildFieldList(requiredFieldNames, null);

    String query =
      'SELECT ' +
      String.join(fields, ', ') +
      ' FROM Product2 WHERE IsActive = true AND Id IN :productIds';

    if (!String.isBlank(jobConfig.CatalogId__c)) {
      Set<Id> productIdsInCatalog = getProductIdsForCatalog(
        jobConfig.CatalogId__c
      );
      if (productIdsInCatalog.isEmpty()) {
        return new List<Product2>();
      }
      query += ' AND Id IN :productIdsInCatalog';
    }

    if (!String.isBlank(jobConfig.ProductFilter__c)) {
      String sanitizedFilter = validateAndSanitizeFilter(
        jobConfig.ProductFilter__c
      );
      query += ' AND (' + sanitizedFilter + ')';
    }

    return Database.query(query);
  }

  public static String getExportedItemId(Product2 product) {
    return String.isNotBlank(product.ProductCode)
      ? product.ProductCode
      : (String) product.Id;
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
