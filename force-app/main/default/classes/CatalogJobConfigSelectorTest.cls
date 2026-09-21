@IsTest
private class CatalogJobConfigSelectorTest {
  private static final String MISSING_DEVELOPER_NAME = 'CatalogJobConfigSelectorTest_Missing';

  private static Set<String> getSelectedFieldNames() {
    Set<String> selectedFieldNames = new Set<String>();

    for (String fieldName : CatalogJobConfigSelector.getFieldNames()) {
      selectedFieldNames.add(fieldName.toLowerCase());
    }

    return selectedFieldNames;
  }

  /**
   * Guards the defect where a config loaded without EnablePayloadLogging__c was
   * handed to the delta export stage, which then failed with "SObject row was
   * retrieved via SOQL without querying the requested field".
   */
  @IsTest
  static void testFieldListCoversEveryCustomField() {
    Set<String> selectedFieldNames = getSelectedFieldNames();
    List<String> missingFieldNames = new List<String>();

    for (
      String fieldName : CatalogJobConfig__mdt.SObjectType.getDescribe()
        .fields.getMap()
        .keySet()
    ) {
      Boolean isLocalCustomField =
        fieldName.endsWithIgnoreCase('__c') &&
        fieldName.countMatches('__') == 1;

      if (
        isLocalCustomField && !selectedFieldNames.contains(fieldName.toLowerCase())
      ) {
        missingFieldNames.add(fieldName);
      }
    }

    System.assertEquals(
      new List<String>(),
      missingFieldNames,
      'Every CatalogJobConfig__mdt custom field must be queried by the shared selector so a config can be passed safely between classes.'
    );
  }

  @IsTest
  static void testFieldListIncludesFieldsReadAcrossClassBoundaries() {
    Set<String> selectedFieldNames = getSelectedFieldNames();

    for (
      String requiredFieldName : new List<String>{
        'enablepayloadlogging__c',
        'availabilitysourceid__c',
        'additionalproductfields__c',
        'buyergroupavailabilitymode__c',
        'syncmode__c',
        'baselinefullconfigdevelopername__c'
      }
    ) {
      System.assert(
        selectedFieldNames.contains(requiredFieldName),
        'Shared selector must query ' + requiredFieldName
      );
    }

    System.assert(
      selectedFieldNames.contains('developername') &&
      selectedFieldNames.contains('label') &&
      selectedFieldNames.contains('masterlabel'),
      'Shared selector must query the identifier and both label fields.'
    );
  }

  @IsTest
  static void testGetFieldNamesReturnsDefensiveCopy() {
    List<String> fieldNames = CatalogJobConfigSelector.getFieldNames();
    Integer originalSize = fieldNames.size();
    fieldNames.clear();

    System.assertEquals(
      originalSize,
      CatalogJobConfigSelector.getFieldNames().size(),
      'Callers must not be able to mutate the shared field list.'
    );
  }

  @IsTest
  static void testEverySelectorQueryExecutes() {
    Test.startTest();
    List<CatalogJobConfig__mdt> allConfigs = CatalogJobConfigSelector.getAll();
    List<CatalogJobConfig__mdt> activeConfigs = CatalogJobConfigSelector.getActive();
    CatalogJobConfig__mdt missingConfig = CatalogJobConfigSelector.findByDeveloperName(
      MISSING_DEVELOPER_NAME
    );
    Map<String, CatalogJobConfig__mdt> configsByName = CatalogJobConfigSelector.getByDeveloperNames(
      new Set<String>{ MISSING_DEVELOPER_NAME }
    );
    List<CatalogJobConfig__mdt> configsBySource = CatalogJobConfigSelector.getActiveBySourceId(
      MISSING_DEVELOPER_NAME
    );
    Test.stopTest();

    System.assertNotEquals(
      null,
      allConfigs,
      'The full config query must execute with the shared field list.'
    );
    System.assert(
      activeConfigs.size() <= allConfigs.size(),
      'Active configs are a subset of all configs.'
    );
    System.assertEquals(null, missingConfig);
    System.assert(configsByName.isEmpty());
    System.assert(configsBySource.isEmpty());
  }

  @IsTest
  static void testBlankInputsSkipQueries() {
    System.assertEquals(null, CatalogJobConfigSelector.findByDeveloperName(null));
    System.assertEquals(null, CatalogJobConfigSelector.findByDeveloperName(''));
    System.assert(CatalogJobConfigSelector.getByDeveloperNames(null).isEmpty());
    System.assert(
      CatalogJobConfigSelector.getByDeveloperNames(new Set<String>()).isEmpty()
    );
    System.assert(CatalogJobConfigSelector.getActiveBySourceId(null).isEmpty());
    System.assert(CatalogJobConfigSelector.getActiveBySourceId('').isEmpty());
  }

  @IsTest
  static void testRequireByDeveloperNamePreservesLegacyErrorMessage() {
    Boolean threw = false;

    try {
      CatalogJobConfigSelector.requireByDeveloperName(MISSING_DEVELOPER_NAME);
    } catch (CatalogJobException e) {
      threw = true;
      System.assert(
        e.getMessage()
          .contains('No CatalogJobConfig__mdt record found with DeveloperName'),
        'Callers and tests depend on the existing not-found message: ' +
        e.getMessage()
      );
    }

    System.assert(threw, 'A missing config must raise CatalogJobException.');
  }
}
