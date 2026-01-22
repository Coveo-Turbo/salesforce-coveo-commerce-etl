public with sharing class CatalogJobRunner {
  @AuraEnabled(cacheable=true)
  public static List<CatalogJobConfig__mdt> listConfigs() {
    return [
      SELECT
        DeveloperName,
        Label,
        CoveoOrgId__c,
        SourceId__c,
        Locale__c,
        IsActive__c,
        ProductFilter__c,
        AdditionalProductFields__c,
        BuilderType__c,
        CatalogId__c,
        BatchSize__c
      FROM CatalogJobConfig__mdt
      ORDER BY Label
    ];
  }

  @AuraEnabled
  public static void runSingle(String jobConfigDeveloperName) {
    List<CatalogJobConfig__mdt> configs = [
      SELECT BatchSize__c
      FROM CatalogJobConfig__mdt
      WHERE DeveloperName = :jobConfigDeveloperName
      LIMIT 1
    ];

    Integer batchSize = 50; // Default batch size
    if (!configs.isEmpty() && configs[0].BatchSize__c != null) {
      batchSize = Integer.valueOf(configs[0].BatchSize__c);
    }

    Database.executeBatch(
      new ProductCatalogExportBatch(jobConfigDeveloperName),
      batchSize
    );
  }

  @AuraEnabled
  public static void runAllActive() {
    List<CatalogJobConfig__mdt> configs = [
      SELECT DeveloperName, IsActive__c, BatchSize__c
      FROM CatalogJobConfig__mdt
      WHERE IsActive__c = TRUE
    ];

    for (CatalogJobConfig__mdt cfg : configs) {
      Integer batchSize = 50; // Default batch size
      if (cfg.BatchSize__c != null) {
        batchSize = Integer.valueOf(cfg.BatchSize__c);
      }

      Database.executeBatch(
        new ProductCatalogExportBatch(cfg.DeveloperName),
        batchSize
      );
    }
  }
}
