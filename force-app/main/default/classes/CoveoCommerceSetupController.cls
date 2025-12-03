/**
 * Controller for the Coveo Commerce ETL Setup LWC component.
 * Provides methods for checking Named Credential status, managing
 * CatalogJobConfig__mdt records, and managing CatalogJsonBuilderMapping__mdt.
 */
public with sharing class CoveoCommerceSetupController {
  private static final String NAMED_CREDENTIAL_NAME = 'Coveo_Push';
  private static final String EXTERNAL_CREDENTIAL_NAME = 'CoveoPushAuthCred';
  private static final String API_KEY_PARAMETER_NAME = 'API_KEY';
  private static final Integer MAX_ERROR_MESSAGE_LENGTH = 200;

  /**
   * Gets the status of the Coveo_Push Named Credential.
   * Returns a map with 'exists' (boolean), 'endpoint' (string), and 'status' (string).
   * Status is only 'Configured' when both the Named Credential exists with an
   * external credential AND the API_KEY authentication parameter is present.
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getNamedCredentialStatus() {
    Map<String, Object> result = new Map<String, Object>();
    result.put('exists', false);
    result.put('endpoint', '');
    result.put('status', 'Not Configured');

    try {
      ConnectApi.NamedCredential nc = ConnectApi.NamedCredentials.getNamedCredential(
        NAMED_CREDENTIAL_NAME
      );

      if (!nc.externalCredentials.isEmpty()) {
        result.put('endpoint', nc.calloutUrl);

        // Check if API_KEY parameter is configured in the external credential
        if (hasApiKeyParameter()) {
          result.put('exists', true);
          result.put('status', 'Configured');
        } else {
          result.put('exists', false);
          result.put('status', 'API Key Missing');
        }
      }
    } catch (Exception e) {
      // Named Credential not accessible or doesn't exist
      result.put('status', 'Error: ' + e.getMessage());
    }

    return result;
  }

  /**
   * Checks if the API_KEY authentication parameter is configured
   * in the CoveoPushAuthCred external credential.
   * @return true if API_KEY parameter exists, false otherwise
   */
  private static Boolean hasApiKeyParameter() {
    try {
      ConnectApi.ExternalCredential ec = ConnectApi.NamedCredentials.getExternalCredential(
        EXTERNAL_CREDENTIAL_NAME
      );

      if (ec.principals != null && !ec.principals.isEmpty()) {
        for (ConnectApi.ExternalCredentialPrincipal principal : ec.principals) {
          if (principal.parameters != null) {
            for (
              ConnectApi.ExternalCredentialParameter param : principal.parameters
            ) {
              if (API_KEY_PARAMETER_NAME.equals(param.parameterName)) {
                // Parameter exists - we consider it configured
                // (we cannot check the actual value as it's encrypted)
                return true;
              }
            }
          }
        }
      }
    } catch (Exception e) {
      // External credential not accessible or doesn't exist
      return false;
    }
    return false;
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

    try {
      CatalogJsonBuilderMapping__mdt defaultMapping = [
        SELECT DeveloperName, MasterLabel, ClassName__c
        FROM CatalogJsonBuilderMapping__mdt
        WHERE DeveloperName = 'Default'
        LIMIT 1
      ];

      defaultBuilder.put('label', defaultMapping.MasterLabel);
      defaultBuilder.put('value', defaultMapping.ClassName__c);
    } catch (Exception e) {
      // Use default if not found
      defaultBuilder.put('label', 'Default Coveo Commerce Builder');
      defaultBuilder.put('value', 'CatalogJsonBuilderCommerce');
    }

    defaultBuilder.put(
      'description',
      'Standard Coveo Commerce catalog builder with ec_* fields'
    );
    options.add(defaultBuilder);

    // Check if there are any other mappings defined
    for (CatalogJsonBuilderMapping__mdt mapping : [
      SELECT DeveloperName, MasterLabel, ClassName__c
      FROM CatalogJsonBuilderMapping__mdt
      WHERE DeveloperName != 'Active' AND DeveloperName != 'Default'
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
   * Tests the Named Credential connection by creating a file container via Push API.
   * This validates both the Named Credential and the API key configuration.
   * Uses the organizationId from the first available CatalogJobConfig__mdt record.
   */
  @AuraEnabled
  public static Map<String, Object> testNamedCredentialConnection() {
    Map<String, Object> result = new Map<String, Object>();
    result.put('success', false);
    result.put('message', '');

    try {
      // Get organizationId from the first available catalog job config
      List<CatalogJobConfig__mdt> configs = [
        SELECT CoveoOrgId__c
        FROM CatalogJobConfig__mdt
        WHERE CoveoOrgId__c != NULL
        LIMIT 1
      ];

      if (configs.isEmpty()) {
        result.put(
          'message',
          'No catalog job configuration found with a Coveo Org ID. Please configure at least one catalog job first.'
        );
        return result;
      }

      String orgId = configs[0].CoveoOrgId__c;

      // Test connection by creating a file container (POST to /organizations/{orgId}/files)
      HttpRequest req = new HttpRequest();
      req.setEndpoint(
        'callout:' +
          NAMED_CREDENTIAL_NAME +
          '/organizations/' +
          orgId +
          '/files'
      );
      req.setMethod('POST');
      req.setTimeout(15000);

      Http http = new Http();
      HttpResponse res = http.send(req);

      Integer statusCode = res.getStatusCode();
      if (statusCode >= 200 && statusCode < 300) {
        result.put('success', true);
        result.put(
          'message',
          'Connection successful! API key and credentials are valid.'
        );
      } else if (statusCode == 401 || statusCode == 403) {
        result.put(
          'message',
          'Authentication failed (HTTP ' +
            statusCode +
            '). Please verify your API key in the External Credential.'
        );
      } else if (statusCode == 404) {
        result.put(
          'message',
          'Organization not found (HTTP 404). Please verify the Coveo Org ID in your catalog configuration.'
        );
      } else {
        String responseBody = res.getBody();
        result.put(
          'message',
          'Connection test returned HTTP ' +
            statusCode +
            '. ' +
            (String.isNotBlank(responseBody)
              ? responseBody.left(MAX_ERROR_MESSAGE_LENGTH)
              : res.getStatus())
        );
      }
    } catch (Exception e) {
      result.put('message', 'Connection failed: ' + e.getMessage());
    }

    return result;
  }
}
