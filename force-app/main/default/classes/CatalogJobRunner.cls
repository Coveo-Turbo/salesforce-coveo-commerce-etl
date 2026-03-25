public with sharing class CatalogJobRunner {
  @AuraEnabled(cacheable=true)
  public static List<CatalogJobConfig__mdt> listConfigs() {
    return [
      SELECT
        DeveloperName,
        Label,
        CoveoOrgId__c,
        SourceId__c,
        AvailabilitySourceId__c,
        WebStoreId__c,
        Locale__c,
        IsActive__c,
        ProductFilter__c,
        AdditionalProductFields__c,
        BuilderType__c,
        CatalogId__c,
        BatchSize__c,
        EnableBuyerGroupAvailability__c
      FROM CatalogJobConfig__mdt
      ORDER BY Label
    ];
  }

  @AuraEnabled
  public static void runSingle(String jobConfigDeveloperName) {
    ProductCatalogExportBatch batch = new ProductCatalogExportBatch(
      jobConfigDeveloperName
    );
    Database.executeBatch(batch, batch.getBatchSize());
  }

  @AuraEnabled
  public static void runSingleAvailability(String jobConfigDeveloperName) {
    BuyerGroupAvailabilityExportBatch batch = new BuyerGroupAvailabilityExportBatch(
      jobConfigDeveloperName
    );
    Database.executeBatch(batch, batch.getBatchSize());
  }

  @AuraEnabled
  public static void runSingleBoth(String jobConfigDeveloperName) {
    runSingle(jobConfigDeveloperName);
    runSingleAvailability(jobConfigDeveloperName);
  }

  @AuraEnabled
  public static void runAllActive() {
    List<CatalogJobConfig__mdt> configs = [
      SELECT DeveloperName, IsActive__c
      FROM CatalogJobConfig__mdt
      WHERE IsActive__c = TRUE
    ];

    for (CatalogJobConfig__mdt cfg : configs) {
      ProductCatalogExportBatch batch = new ProductCatalogExportBatch(
        cfg.DeveloperName
      );
      Database.executeBatch(batch, batch.getBatchSize());
    }
  }

  @AuraEnabled
  public static void runAllActiveAvailability() {
    List<CatalogJobConfig__mdt> configs = [
      SELECT DeveloperName, EnableBuyerGroupAvailability__c
      FROM CatalogJobConfig__mdt
      WHERE IsActive__c = TRUE AND EnableBuyerGroupAvailability__c = TRUE
    ];

    for (CatalogJobConfig__mdt cfg : configs) {
      BuyerGroupAvailabilityExportBatch batch = new BuyerGroupAvailabilityExportBatch(
        cfg.DeveloperName
      );
      Database.executeBatch(batch, batch.getBatchSize());
    }
  }

  @AuraEnabled
  public static void runAllActiveBoth() {
    runAllActive();
    runAllActiveAvailability();
  }
}
