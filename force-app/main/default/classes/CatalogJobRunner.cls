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
        BuilderType__c
      FROM CatalogJobConfig__mdt
      ORDER BY Label
    ];
  }

  @AuraEnabled
  public static void runSingle(String jobConfigDeveloperName) {
    Database.executeBatch(
      new ProductCatalogExportBatch(jobConfigDeveloperName),
      100
    );
  }

  @AuraEnabled
  public static void runAllActive() {
    List<CatalogJobConfig__mdt> configs = [
      SELECT DeveloperName, IsActive__c
      FROM CatalogJobConfig__mdt
      WHERE IsActive__c = TRUE
    ];

    for (CatalogJobConfig__mdt cfg : configs) {
      Database.executeBatch(
        new ProductCatalogExportBatch(cfg.DeveloperName),
        100
      );
    }
  }
}
