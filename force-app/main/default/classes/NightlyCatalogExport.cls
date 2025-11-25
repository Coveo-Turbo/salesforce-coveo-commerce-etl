global with sharing class NightlyCatalogExport implements Schedulable {
  global void execute(SchedulableContext sc) {
    Database.executeBatch(
      new ProductCatalogExportBatch(
        'REPLACE_WITH_COVEO_ORG_ID',
        'REPLACE_WITH_SOURCE_ID'
      ),
      100
    );
  }
}
