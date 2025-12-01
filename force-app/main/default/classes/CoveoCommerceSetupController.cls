/**
 * Controller for the Coveo Commerce ETL Setup LWC component.
 * Provides methods for checking Named Credential status, managing
 * CatalogJobConfig__mdt records, and managing CatalogJsonBuilderMapping__mdt.
 */
public with sharing class CoveoCommerceSetupController {
  private static final String NAMED_CREDENTIAL_NAME = 'Coveo_Push';

  /**
   * Gets the status of the Coveo_Push Named Credential.
   * Returns a map with 'exists' (boolean), 'endpoint' (string), and 'status' (string).
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getNamedCredentialStatus() {
    Map<String, Object> result = new Map<String, Object>();
    result.put('exists', false);
    result.put('endpoint', '');
    result.put('status', 'Not Configured');

    try {
      // Query Named Credential metadata to check if it exists
      List<NamedCredential> creds = [
        SELECT Id, DeveloperName, Endpoint
        FROM NamedCredential
        WHERE DeveloperName = :NAMED_CREDENTIAL_NAME
        LIMIT 1
      ];

      if (!creds.isEmpty()) {
        result.put('exists', true);
        result.put('endpoint', creds[0].Endpoint);
        result.put('status', 'Configured');
      }
    } catch (Exception e) {
      // Named Credential not accessible or doesn't exist
      result.put('status', 'Error: ' + e.getMessage());
    }

    return result;
  }

  /**
   * Gets all CatalogJobConfig__mdt records for display.
   */
  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getCatalogJobConfigs() {
    List<Map<String, Object>> configs = new List<Map<String, Object>>();

    for (CatalogJobConfig__mdt cfg : [
      SELECT
        Id,
        DeveloperName,
        MasterLabel,
        CoveoOrgId__c,
        SourceId__c,
        Locale__c,
        IsActive__c,
        ProductFilter__c,
        AdditionalProductFields__c
      FROM CatalogJobConfig__mdt
      ORDER BY MasterLabel
    ]) {
      Map<String, Object> configMap = new Map<String, Object>();
      configMap.put('id', cfg.Id);
      configMap.put('developerName', cfg.DeveloperName);
      configMap.put('label', cfg.MasterLabel);
      configMap.put('coveoOrgId', cfg.CoveoOrgId__c);
      configMap.put('sourceId', cfg.SourceId__c);
      configMap.put('locale', cfg.Locale__c);
      configMap.put('isActive', cfg.IsActive__c);
      configMap.put('productFilter', cfg.ProductFilter__c);
      configMap.put('additionalProductFields', cfg.AdditionalProductFields__c);
      configs.add(configMap);
    }

    return configs;
  }

  /**
   * Gets the current active builder mapping.
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getActiveBuilderMapping() {
    Map<String, Object> result = new Map<String, Object>();
    result.put('className', 'CatalogJsonBuilderCommerce');
    result.put('isDefault', true);

    try {
      CatalogJsonBuilderMapping__mdt mapping = [
        SELECT DeveloperName, MasterLabel, ClassName__c
        FROM CatalogJsonBuilderMapping__mdt
        WHERE DeveloperName = 'Active'
        LIMIT 1
      ];

      result.put('className', mapping.ClassName__c);
      result.put('label', mapping.MasterLabel);
      result.put(
        'isDefault',
        mapping.ClassName__c == 'CatalogJsonBuilderCommerce'
      );
    } catch (Exception e) {
      // Use default if not found
    }

    return result;
  }

  /**
   * Gets all available builder class options.
   * Currently returns the built-in builder; customers can extend by
   * creating their own implementations.
   */
  @AuraEnabled(cacheable=true)
  public static List<Map<String, String>> getBuilderClassOptions() {
    List<Map<String, String>> options = new List<Map<String, String>>();

    // Add default builder
    Map<String, String> defaultBuilder = new Map<String, String>();
    defaultBuilder.put('label', 'Commerce Catalog Builder (Default)');
    defaultBuilder.put('value', 'CatalogJsonBuilderCommerce');
    defaultBuilder.put(
      'description',
      'Standard Coveo Commerce catalog builder with ec_* fields'
    );
    options.add(defaultBuilder);

    // Check if there are any other mappings defined
    for (CatalogJsonBuilderMapping__mdt mapping : [
      SELECT DeveloperName, MasterLabel, ClassName__c
      FROM CatalogJsonBuilderMapping__mdt
      WHERE DeveloperName != 'Active'
    ]) {
      Map<String, String> option = new Map<String, String>();
      option.put('label', mapping.MasterLabel);
      option.put('value', mapping.ClassName__c);
      option.put('description', 'Custom builder: ' + mapping.ClassName__c);
      options.add(option);
    }

    return options;
  }

  /**
   * Validates that a builder class exists and implements ICatalogJsonBuilder.
   */
  @AuraEnabled
  public static Map<String, Object> validateBuilderClass(String className) {
    Map<String, Object> result = new Map<String, Object>();
    result.put('isValid', false);
    result.put('message', '');

    if (String.isBlank(className)) {
      result.put('message', 'Class name cannot be empty');
      return result;
    }

    try {
      Type builderType = Type.forName(className);
      if (builderType == null) {
        result.put('message', 'Class "' + className + '" not found');
        return result;
      }

      // Try to instantiate and verify it implements ICatalogJsonBuilder
      Object instance = builderType.newInstance();
      if (!(instance instanceof ICatalogJsonBuilder)) {
        result.put(
          'message',
          'Class "' + className + '" does not implement ICatalogJsonBuilder'
        );
        return result;
      }

      result.put('isValid', true);
      result.put(
        'message',
        'Class is valid and implements ICatalogJsonBuilder'
      );
    } catch (Exception e) {
      result.put('message', 'Error validating class: ' + e.getMessage());
    }

    return result;
  }

  /**
   * Tests the Named Credential connection by making a lightweight call.
   */
  @AuraEnabled
  public static Map<String, Object> testNamedCredentialConnection() {
    Map<String, Object> result = new Map<String, Object>();
    result.put('success', false);
    result.put('message', '');

    try {
      HttpRequest req = new HttpRequest();
      req.setEndpoint('callout:' + NAMED_CREDENTIAL_NAME);
      req.setMethod('GET');
      req.setTimeout(10000);

      Http http = new Http();
      HttpResponse res = http.send(req);

      Integer statusCode = res.getStatusCode();
      if (statusCode >= 200 && statusCode < 400) {
        result.put('success', true);
        result.put(
          'message',
          'Connection successful (HTTP ' + statusCode + ')'
        );
      } else if (statusCode == 401 || statusCode == 403) {
        result.put(
          'message',
          'Authentication failed. Please verify your API key.'
        );
      } else {
        result.put('message', 'Connection test returned HTTP ' + statusCode);
      }
    } catch (Exception e) {
      result.put('message', 'Connection failed: ' + e.getMessage());
    }

    return result;
  }
}
