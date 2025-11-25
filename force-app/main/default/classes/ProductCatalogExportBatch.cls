global with sharing class ProductCatalogExportBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
  private final String orgId;
  private final String sourceId;
  private final Id stdPricebookId;

  public ProductCatalogExportBatch(String orgId, String sourceId) {
    this.orgId = orgId;
    this.sourceId = sourceId;
    this.stdPricebookId = [
      SELECT Id
      FROM Pricebook2
      WHERE IsStandard = TRUE
      LIMIT 1
    ]
    .Id;
  }

  global Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(
      [
        SELECT
          Id,
          Name,
          StockKeepingUnit,
          Family,
          Brand__c,
          Image_URL__c,
          Product_URL__c,
          In_Stock__c
        FROM Product2
        WHERE IsActive = TRUE
      ]
    );
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
    Blob ndjson = Blob.valueOf(builder.buildFullUpdateNdjson(scope, pbes));

    CoveoStreamClient client = new CoveoStreamClient(orgId, sourceId);
    Map<String, Object> container = client.createFileContainer();
    client.uploadNdjson(
      (String) container.get('uploadUri'),
      (Map<String, Object>) container.get('requiredHeaders'),
      ndjson
    );
    client.streamUpdate((String) container.get('fileId'));
  }

  global void finish(Database.BatchableContext bc) {
    // Optional: log/publish a Platform Event
  }
}
