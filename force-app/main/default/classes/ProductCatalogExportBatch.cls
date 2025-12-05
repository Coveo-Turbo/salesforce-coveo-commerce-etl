/**
 * Batch job that exports Product2 records to Coveo catalog source.
 *
 * SECURITY NOTE: The ProductFilter__c field in CatalogJobConfig__mdt is used to build
 * dynamic SOQL queries. This field should only contain valid SOQL WHERE clause fragments
 * (e.g., "Family = 'Electronics'" or "ProductCode LIKE 'SKU-%'").
 *
 * Since CatalogJobConfig__mdt is Custom Metadata, only users with the appropriate
 * permissions (typically admins/developers) can modify it. However, administrators
 * should ensure that ProductFilter__c values:
 * - Contain only valid SOQL field references and operators
 * - Do not include DML operations or subqueries that could cause security issues
 * - Are tested before deployment to production
 */
global with sharing class ProductCatalogExportBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
  private final CatalogJobConfig__mdt jobConfig;
  private final List<String> extraFieldNames = new List<String>();
  private final Id stdPricebookId;

  // Track highest orderingId across execute() calls
  public Long latestOrderingId;
  public List<Coveo_Payload_Log__c> payloadLogs = new List<Coveo_Payload_Log__c>();

  public ProductCatalogExportBatch(String jobConfigDeveloperName) {
    List<CatalogJobConfig__mdt> configs = [
      SELECT
        DeveloperName,
        Label,
        CoveoOrgId__c,
        SourceId__c,
        Locale__c,
        IsActive__c,
        ProductFilter__c,
        AdditionalProductFields__c,
        BuilderType__c
      FROM CatalogJobConfig__mdt
      WHERE DeveloperName = :jobConfigDeveloperName
      LIMIT 1
    ];

    if (configs.isEmpty()) {
      throw new CatalogJobException(
        'No CatalogJobConfig__mdt record found with DeveloperName: ' +
        jobConfigDeveloperName
      );
    }
    this.jobConfig = configs[0];

    if (!String.isBlank(jobConfig.AdditionalProductFields__c)) {
      for (String f : jobConfig.AdditionalProductFields__c.split(',')) {
        String trimmed = f.trim();
        if (String.isNotBlank(trimmed) && !extraFieldNames.contains(trimmed)) {
          extraFieldNames.add(trimmed);
        }
      }
    }
    this.stdPricebookId = [
      SELECT Id
      FROM Pricebook2
      WHERE IsStandard = TRUE
      LIMIT 1
    ]
    .Id;
  }

  global Database.QueryLocator start(Database.BatchableContext bc) {
    // Base fields required for catalog
    List<String> fields = new List<String>{
      'Id',
      'Name',
      'StockKeepingUnit',
      'Family',
      'ProductCode',
      'Description',
      'QuantityUnitOfMeasure',
      'IsActive',
      'Type',
      'DisplayUrl'
    };

    // Add extra fields from config
    for (String apiName : extraFieldNames) {
      if (!fields.contains(apiName)) {
        fields.add(apiName);
      }
    }

    String selectClause = String.join(fields, ', ');

    String baseQuery =
      'SELECT ' +
      selectClause +
      ' FROM Product2 WHERE IsActive = true';

    if (!String.isBlank(jobConfig.ProductFilter__c)) {
      String sanitizedFilter = validateAndSanitizeFilter(
        jobConfig.ProductFilter__c
      );
      baseQuery += ' AND (' + sanitizedFilter + ')';
    }

    System.debug('ProductCatalogExportBatch.start SOQL: ' + baseQuery);
    return Database.getQueryLocator(baseQuery);
  }

  global void execute(Database.BatchableContext bc, List<Product2> scope) {
    Map<Id, PricebookEntry> pbesByProduct = new Map<Id, PricebookEntry>();

    for (PricebookEntry pbe : [
      SELECT Id, Product2Id, UnitPrice
      FROM PricebookEntry
      WHERE Pricebook2Id = :stdPricebookId AND Product2Id IN :scope
    ]) {
      if (pbe.Product2Id != null) {
        pbesByProduct.put(pbe.Product2Id, pbe);
      }
    }
    ICatalogJsonBuilder builder = CatalogJsonBuilderFactory.getForBuilderType(
      jobConfig.BuilderType__c
    );
    String ndjsonPayload = builder.buildFullUpdateNdjson(
      scope,
      pbesByProduct,
      extraFieldNames
    );

    System.debug(
      LoggingLevel.INFO,
      'CatalogExport NDJSON payload: ' + ndjsonPayload
    );

    // Validate locally
    CoveoPayloadValidator.Result vr = CoveoPayloadValidator.validate(
      ndjsonPayload
    );
    System.debug('Coveo payload validation: ' + JSON.serialize(vr));

    // Log to custom object (optional but super helpful)
    Coveo_Payload_Log__c log = new Coveo_Payload_Log__c(
      ScopeSize__c = scope.size(),
      OperationCount__c = vr.operationCount,
      IsValid__c = vr.isValid,
      Reason__c = vr.reason,
      Payload__c = ndjsonPayload.left(32000) // guard against LT max
    );
    payloadLogs.add(log);

    Blob ndjson = Blob.valueOf(ndjsonPayload);

    CoveoStreamClient client = new CoveoStreamClient(
      jobConfig.CoveoOrgId__c,
      jobConfig.SourceId__c
    );
    Map<String, Object> container = client.createFileContainer();
    System.debug(
      LoggingLevel.DEBUG,
      'Coveo file container response: ' + JSON.serialize(container)
    );
    client.uploadNdjson(
      (String) container.get('uploadUri'),
      (Map<String, Object>) container.get('requiredHeaders'),
      ndjson
    );

    String updateResponse = client.streamUpdate(
      (String) container.get('fileId')
    );

    // Parse orderingId from response body
    Map<String, Object> resMap = (Map<String, Object>) JSON.deserializeUntyped(
      updateResponse
    );

    if (resMap.containsKey('orderingId')) {
      Long oid = Long.valueOf(String.valueOf(resMap.get('orderingId')));
      if (latestOrderingId == null || oid > latestOrderingId) {
        latestOrderingId = oid;
      }
    }
  }

  global void finish(Database.BatchableContext bc) {
    System.debug(
      'ProductCatalogExportBatch.finish: latestOrderingId=' + latestOrderingId
    );

    // Delete older items for this specific source
    CoveoDeleteOlderThan.deleteOlderThan(
      jobConfig.CoveoOrgId__c,
      jobConfig.SourceId__c,
      latestOrderingId
    );

    // Insert logs if any
    if (!payloadLogs.isEmpty()) {
      try {
        insert payloadLogs;
      } catch (DmlException e) {
        System.debug(
          LoggingLevel.WARN,
          'Failed to insert payload logs: ' + e.getMessage()
        );
      }
    }
  }

  /**
   * Validates and sanitizes the ProductFilter__c value before using it in dynamic SOQL.
   * While Custom Metadata is developer-controlled, this method provides an additional
   * layer of protection against malformed queries and potential injection patterns.
   *
   * @param filter The raw filter string from CatalogJobConfig__mdt.ProductFilter__c
   * @return The validated filter string safe for use in SOQL
   * @throws CatalogJobException if the filter contains potentially dangerous patterns
   */
  @TestVisible
  private static String validateAndSanitizeFilter(String filter) {
    if (String.isBlank(filter)) {
      return filter;
    }

    String trimmedFilter = filter.trim();

    // Normalize whitespace for pattern detection (replace tabs/newlines with spaces)
    String normalizedFilter = trimmedFilter.replaceAll('[\\t\\n\\r]+', ' ')
      .toUpperCase();

    // Check for DML keywords that shouldn't appear in a WHERE clause filter
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

    // Check for subqueries by looking for SELECT...FROM pattern
    // This is a simplified check - subqueries in WHERE clauses are generally unexpected
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
