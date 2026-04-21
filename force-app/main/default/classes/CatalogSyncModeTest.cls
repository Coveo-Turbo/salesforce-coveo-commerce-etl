@IsTest
private class CatalogSyncModeTest {
  @IsTest
  static void testResolve_defaultsToFull() {
    System.assertEquals(CatalogSyncMode.FULL, CatalogSyncMode.resolve((String) null));
    System.assertEquals(CatalogSyncMode.FULL, CatalogSyncMode.resolve(''));
    System.assertEquals(CatalogSyncMode.FULL, CatalogSyncMode.resolve('Full'));
  }

  @IsTest
  static void testResolve_acceptsDeltaCaseInsensitively() {
    System.assertEquals(CatalogSyncMode.DELTA, CatalogSyncMode.resolve('Delta'));
    System.assertEquals(CatalogSyncMode.DELTA, CatalogSyncMode.resolve('delta'));
    System.assertEquals(CatalogSyncMode.DELTA, CatalogSyncMode.resolve(' DELTA '));
  }

  @IsTest
  static void testIsSupportedValue_rejectsUnknownModes() {
    System.assertEquals(true, CatalogSyncMode.isSupportedValue(null));
    System.assertEquals(true, CatalogSyncMode.isSupportedValue('full'));
    System.assertEquals(true, CatalogSyncMode.isSupportedValue('delta'));
    System.assertEquals(false, CatalogSyncMode.isSupportedValue('hourly'));
  }

  @IsTest
  static void testIsDeltaAndIsFull_useResolvedMode() {
    CatalogJobConfig__mdt fullConfig = new CatalogJobConfig__mdt(
      SyncMode__c = 'Full'
    );
    CatalogJobConfig__mdt deltaConfig = new CatalogJobConfig__mdt(
      SyncMode__c = 'Delta'
    );

    System.assertEquals(true, CatalogSyncMode.isFull(fullConfig));
    System.assertEquals(false, CatalogSyncMode.isDelta(fullConfig));
    System.assertEquals(true, CatalogSyncMode.isDelta(deltaConfig));
    System.assertEquals(false, CatalogSyncMode.isFull(deltaConfig));
  }
}
