global with sharing class ProductCatalogExportBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
  private final CatalogJobConfig__mdt jobConfig;
  private final List<String> extraFieldNames = new List<String>();
  private final Id stdPricebookId;

  // Track highest orderingId across execute() calls
  public Long latestOrderingId;
  public List<Coveo_Payload_Log__c> payloadLogs = new List<Coveo_Payload_Log__c>();

  public ProductCatalogExportBatch(String jobConfigDeveloperName) {
    this.jobConfig = [
      SELECT
        DeveloperName,
        Label,
        CoveoOrgId__c,
        SourceId__c,
        Locale__c,
        IsActive__c,
        ProductFilter__c,
        AdditionalProductFields__c
      FROM CatalogJobConfig__mdt
      WHERE DeveloperName = :jobConfigDeveloperName
      LIMIT 1
    ];

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
      baseQuery += ' AND (' + jobConfig.ProductFilter__c + ')';
    }

    System.debug('ProductCatalogExportBatch.start SOQL: ' + baseQuery);
    return Database.getQueryLocator(baseQuery);
  }

  global void execute(Database.BatchableContext bc, List<Product2> scope) {
    Map<Id, PricebookEntry> pbes = new Map<Id, PricebookEntry>(
      [
        SELECT Id, Product2Id, UnitPrice
        FROM PricebookEntry
        WHERE Pricebook2Id = :stdPricebookId AND Product2Id IN :scope
      ]
    );
    ICatalogJsonBuilder builder = CatalogJsonBuilderFactory.get();
    String ndjsonPayload = builder.buildFullUpdateNdjson(
      scope,
      pbes,
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
}
