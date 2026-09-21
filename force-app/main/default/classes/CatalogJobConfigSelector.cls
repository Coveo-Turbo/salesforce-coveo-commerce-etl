/**
 * Single source of truth for every CatalogJobConfig__mdt query.
 *
 * Hand-maintained SELECT lists previously drifted between classes. When a
 * config loaded by one class was passed to another class that read a field the
 * first class did not query, the second class failed at runtime with
 * "SObject row was retrieved via SOQL without querying the requested field".
 * Loading every config through this selector keeps the field list complete and
 * identical for all callers.
 */
public with sharing class CatalogJobConfigSelector {
  @TestVisible
  private static final List<String> FIELD_NAMES = new List<String>{
    'Id',
    'DeveloperName',
    'Label',
    'MasterLabel',
    'AdditionalProductFields__c',
    'AvailabilitySourceId__c',
    'BaselineFullConfigDeveloperName__c',
    'BatchSize__c',
    'BuilderType__c',
    'BuyerGroupAvailabilityMode__c',
    'CatalogId__c',
    'CoveoOrgId__c',
    'EnableBuyerGroupAvailability__c',
    'EnablePayloadLogging__c',
    'IsActive__c',
    'Locale__c',
    'PricebookIds__c',
    'ProductFilter__c',
    'SourceId__c',
    'SyncMode__c',
    'WebStoreId__c',
    'WebStoreIds__c'
  };

  public static List<String> getFieldNames() {
    return new List<String>(FIELD_NAMES);
  }

  @TestVisible
  private static String buildBaseQuery() {
    return 'SELECT ' +
      String.join(FIELD_NAMES, ', ') +
      ' FROM CatalogJobConfig__mdt';
  }

  public static List<CatalogJobConfig__mdt> getAll() {
    return (List<CatalogJobConfig__mdt>) Database.query(
      buildBaseQuery() + ' ORDER BY MasterLabel'
    );
  }

  public static List<CatalogJobConfig__mdt> getActive() {
    return (List<CatalogJobConfig__mdt>) Database.query(
      buildBaseQuery() + ' WHERE IsActive__c = TRUE ORDER BY MasterLabel'
    );
  }

  public static CatalogJobConfig__mdt findByDeveloperName(
    String developerName
  ) {
    if (String.isBlank(developerName)) {
      return null;
    }

    List<CatalogJobConfig__mdt> configs = (List<CatalogJobConfig__mdt>) Database.query(
      buildBaseQuery() + ' WHERE DeveloperName = :developerName LIMIT 1'
    );

    return configs.isEmpty() ? null : configs[0];
  }

  public static CatalogJobConfig__mdt requireByDeveloperName(
    String developerName
  ) {
    CatalogJobConfig__mdt config = findByDeveloperName(developerName);

    if (config == null) {
      throw new CatalogJobException(
        'No CatalogJobConfig__mdt record found with DeveloperName: ' +
        developerName
      );
    }

    return config;
  }

  public static Map<String, CatalogJobConfig__mdt> getByDeveloperNames(
    Set<String> developerNames
  ) {
    Map<String, CatalogJobConfig__mdt> configsByDeveloperName = new Map<String, CatalogJobConfig__mdt>();

    if (developerNames == null || developerNames.isEmpty()) {
      return configsByDeveloperName;
    }

    for (
      CatalogJobConfig__mdt config : (List<CatalogJobConfig__mdt>) Database.query(
        buildBaseQuery() + ' WHERE DeveloperName IN :developerNames'
      )
    ) {
      configsByDeveloperName.put(config.DeveloperName, config);
    }

    return configsByDeveloperName;
  }

  public static List<CatalogJobConfig__mdt> getActiveBySourceId(
    String sourceId
  ) {
    if (String.isBlank(sourceId)) {
      return new List<CatalogJobConfig__mdt>();
    }

    return (List<CatalogJobConfig__mdt>) Database.query(
      buildBaseQuery() + ' WHERE SourceId__c = :sourceId AND IsActive__c = TRUE'
    );
  }
}
