@IsTest
private class CatalogBuyerGroupAvailabilityModeTest {
  @IsTest
  static void testResolve_usesExplicitModeBeforeLegacyFallback() {
    CatalogJobConfig__mdt embeddedConfig = new CatalogJobConfig__mdt(
      BuyerGroupAvailabilityMode__c = CatalogBuyerGroupAvailabilityMode.EMBEDDED,
      EnableBuyerGroupAvailability__c = false
    );
    CatalogJobConfig__mdt legacyEnabledConfig = new CatalogJobConfig__mdt(
      EnableBuyerGroupAvailability__c = true
    );
    CatalogJobConfig__mdt legacyDisabledConfig = new CatalogJobConfig__mdt(
      EnableBuyerGroupAvailability__c = false
    );

    System.assertEquals(
      CatalogBuyerGroupAvailabilityMode.EMBEDDED,
      CatalogBuyerGroupAvailabilityMode.resolve(embeddedConfig)
    );
    System.assertEquals(
      CatalogBuyerGroupAvailabilityMode.PAIRED_SOURCE,
      CatalogBuyerGroupAvailabilityMode.resolve(legacyEnabledConfig)
    );
    System.assertEquals(
      CatalogBuyerGroupAvailabilityMode.DISABLED,
      CatalogBuyerGroupAvailabilityMode.resolve(legacyDisabledConfig)
    );
  }

  @IsTest
  static void testModeFlags_coverPairedAndEmbedded() {
    System.assertEquals(
      true,
      CatalogBuyerGroupAvailabilityMode.usesPairedSource(
        CatalogBuyerGroupAvailabilityMode.PAIRED_SOURCE
      )
    );
    System.assertEquals(
      false,
      CatalogBuyerGroupAvailabilityMode.usesEmbedded(
        CatalogBuyerGroupAvailabilityMode.PAIRED_SOURCE
      )
    );
    System.assertEquals(
      false,
      CatalogBuyerGroupAvailabilityMode.usesPairedSource(
        CatalogBuyerGroupAvailabilityMode.EMBEDDED
      )
    );
    System.assertEquals(
      true,
      CatalogBuyerGroupAvailabilityMode.usesEmbedded(
        CatalogBuyerGroupAvailabilityMode.EMBEDDED
      )
    );
  }

  @IsTest
  static void testDraftResolution_supportsAliasesAndLabels() {
    System.assertEquals(
      CatalogBuyerGroupAvailabilityMode.PAIRED_SOURCE,
      CatalogBuyerGroupAvailabilityMode.resolveDraftMode('paired')
    );
    System.assertEquals(
      true,
      CatalogBuyerGroupAvailabilityMode.isSupportedValue('paired')
    );
    System.assertEquals(
      false,
      CatalogBuyerGroupAvailabilityMode.isSupportedValue('banana')
    );
    System.assertEquals(
      'Embedded On Product Documents',
      CatalogBuyerGroupAvailabilityMode.getLabel(
        CatalogBuyerGroupAvailabilityMode.EMBEDDED
      )
    );
    System.assertEquals(
      CatalogBuyerGroupAvailabilityMode.DISABLED,
      CatalogBuyerGroupAvailabilityMode.resolveDraftMode(null)
    );
  }

  @IsTest
  static void testResolveAndLabels_coverNullConfigAndRemainingLabels() {
    System.assertEquals(
      CatalogBuyerGroupAvailabilityMode.DISABLED,
      CatalogBuyerGroupAvailabilityMode.resolve(null)
    );
    System.assertEquals(
      'Paired Availability Source',
      CatalogBuyerGroupAvailabilityMode.getLabel(
        CatalogBuyerGroupAvailabilityMode.PAIRED_SOURCE
      )
    );
    System.assertEquals(
      'Disabled',
      CatalogBuyerGroupAvailabilityMode.getLabel('banana')
    );
  }
}
