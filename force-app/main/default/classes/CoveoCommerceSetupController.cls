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
  private static final Integer OPTION_QUERY_LIMIT = 200;
  private static final String SCHEDULE_CADENCE_MINUTES = 'Minutes';
  private static final String SCHEDULE_CADENCE_HOURLY = 'Hourly';
  private static final String SCHEDULE_CADENCE_WEEKLY = 'Weekly';
  private static final Set<String> EXCLUDED_PRODUCT_FIELD_API_NAMES = new Set<String>{
    'CreatedById',
    'CreatedDate',
    'Id',
    'IsDeleted',
    'LastModifiedById',
    'LastModifiedDate',
    'LastReferencedDate',
    'LastViewedDate',
    'MasterRecordId',
    'SystemModstamp'
  };

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
        if (isExternalCredentialConfigured()) {
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
   * We can't inspect individual auth param names (e.g., 'API_KEY') from Apex.
   * Instead, we treat 'Configured' or 'Unknown' authentication status on any principal
   * as "API Key is configured".
   */
  private static Boolean isExternalCredentialConfigured() {
    try {
      ConnectApi.ExternalCredential ec = ConnectApi.NamedCredentials.getExternalCredential(
        EXTERNAL_CREDENTIAL_NAME
      );

      if (ec == null || ec.principals == null || ec.principals.isEmpty()) {
        return false;
      }

      for (ConnectApi.ExternalCredentialPrincipal principal : ec.principals) {
        String status = String.valueOf(principal.authenticationStatus);
        System.debug(
          'Principal: ' +
            principal.principalName +
            ', status=' +
            principal.authenticationStatus
        );
        // Values: Configured, NotConfigured, Unknown
        if (status != 'NotConfigured') {
          return true; // "has required credentials for at least one principal"
        }
      }
      return false;
    } catch (Exception e) {
      return false;
    }
  }

  /**
   * Gets all CatalogJobConfig__mdt records for display.
   */
  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getCatalogJobConfigs() {
    List<Map<String, Object>> configs = new List<Map<String, Object>>();
    List<CatalogJobConfig__mdt> configRecords = [
      SELECT
        Id,
        DeveloperName,
        MasterLabel,
        CoveoOrgId__c,
        SourceId__c,
        AvailabilitySourceId__c,
        BuyerGroupAvailabilityMode__c,
        WebStoreId__c,
        Locale__c,
        IsActive__c,
        ProductFilter__c,
        AdditionalProductFields__c,
        BuilderType__c,
        CatalogId__c,
        EnableBuyerGroupAvailability__c,
        SyncMode__c,
        BaselineFullConfigDeveloperName__c
      FROM CatalogJobConfig__mdt
      ORDER BY MasterLabel
    ];
    Map<String, CatalogSyncStateService.Snapshot> snapshotsByDeveloperName = CatalogSyncStateService.getSnapshotsByDeveloperName(
      configRecords
    );
    Map<String, CatalogProductSyncScheduler.ScheduleSnapshot> scheduleSnapshotsByDeveloperName = CatalogProductSyncScheduler.getScheduleSnapshotsByDeveloperName(
      configRecords
    );

    for (CatalogJobConfig__mdt cfg : configRecords) {
      CatalogSyncStateService.Snapshot snapshot = snapshotsByDeveloperName.get(
        cfg.DeveloperName
      );
      CatalogProductSyncScheduler.ScheduleSnapshot scheduleSnapshot = scheduleSnapshotsByDeveloperName.get(
        cfg.DeveloperName
      );
      Map<String, Object> configMap = new Map<String, Object>();
      configMap.put('id', cfg.Id);
      configMap.put('developerName', cfg.DeveloperName);
      configMap.put('label', cfg.MasterLabel);
      configMap.put('coveoOrgId', cfg.CoveoOrgId__c);
      configMap.put('sourceId', cfg.SourceId__c);
      configMap.put('availabilitySourceId', cfg.AvailabilitySourceId__c);
      configMap.put(
        'buyerGroupAvailabilityMode',
        CatalogBuyerGroupAvailabilityMode.resolve(cfg)
      );
      configMap.put('webStoreId', cfg.WebStoreId__c);
      configMap.put('locale', cfg.Locale__c);
      configMap.put('isActive', cfg.IsActive__c);
      configMap.put('productFilter', cfg.ProductFilter__c);
      configMap.put('additionalProductFields', cfg.AdditionalProductFields__c);
      configMap.put(
        'buyerGroupAvailabilityEnabled',
        CatalogBuyerGroupAvailabilityMode.isBuyerGroupAccessEnabled(cfg)
      );
      configMap.put(
        'builderType',
        String.isNotBlank(cfg.BuilderType__c)
          ? cfg.BuilderType__c
          : '(Global Default)'
      );
      configMap.put('catalogId', cfg.CatalogId__c);
      configMap.put('syncMode', CatalogSyncMode.resolve(cfg));
      configMap.put(
        'baselineFullConfigDeveloperName',
        cfg.BaselineFullConfigDeveloperName__c
      );
      configMap.put(
        'deltaReady',
        snapshot == null ? true : snapshot.deltaReady
      );
      configMap.put(
        'deltaReadinessMessage',
        snapshot == null ? null : snapshot.deltaReadinessMessage
      );
      configMap.put(
        'lastSuccessfulFullSyncAt',
        snapshot == null ? null : snapshot.lastSuccessfulFullSyncAt
      );
      configMap.put(
        'lastSuccessfulSyncAt',
        snapshot == null ? null : snapshot.lastSuccessfulSyncAt
      );
      configMap.put(
        'lastRunMode',
        snapshot == null ? null : snapshot.lastRunMode
      );
      configMap.put(
        'lastSuccessfulConfigDeveloperName',
        snapshot == null ? null : snapshot.lastSuccessfulConfigDeveloperName
      );
      configMap.put(
        'isScheduled',
        scheduleSnapshot == null ? false : scheduleSnapshot.isScheduled
      );
      configMap.put(
        'scheduledJobName',
        scheduleSnapshot == null ? null : scheduleSnapshot.jobName
      );
      configMap.put(
        'scheduleState',
        scheduleSnapshot == null ? null : scheduleSnapshot.state
      );
      configMap.put(
        'scheduleCronExpression',
        scheduleSnapshot == null ? null : scheduleSnapshot.cronExpression
      );
      configMap.put(
        'scheduleNextFireTime',
        scheduleSnapshot == null ? null : scheduleSnapshot.nextFireTime
      );
      configMap.put(
        'schedulePreviousFireTime',
        scheduleSnapshot == null ? null : scheduleSnapshot.previousFireTime
      );
      configMap.put(
        'scheduleTimesTriggered',
        scheduleSnapshot == null ? null : scheduleSnapshot.timesTriggered
      );
      configMap.put(
        'scheduleCadenceRecognized',
        scheduleSnapshot == null ? false : scheduleSnapshot.cadenceRecognized
      );
      configMap.put(
        'scheduleCadenceType',
        scheduleSnapshot == null ? null : scheduleSnapshot.cadenceType
      );
      configMap.put(
        'scheduleIntervalMinutes',
        scheduleSnapshot == null ? null : scheduleSnapshot.intervalMinutes
      );
      configMap.put(
        'scheduleIntervalHours',
        scheduleSnapshot == null ? null : scheduleSnapshot.intervalHours
      );
      configMap.put(
        'scheduleDayOfWeek',
        scheduleSnapshot == null ? null : scheduleSnapshot.dayOfWeek
      );
      configMap.put(
        'scheduleHourOfDay',
        scheduleSnapshot == null ? null : scheduleSnapshot.hourOfDay
      );
      configMap.put(
        'scheduleMinuteOfHour',
        scheduleSnapshot == null ? null : scheduleSnapshot.minuteOfHour
      );
      configs.add(configMap);
    }

    return configs;
  }

  /**
   * Creates or replaces the native Salesforce scheduled job for a catalog sync config.
   */
  @AuraEnabled
  public static Map<String, Object> saveCatalogJobSchedule(
    String jobConfigDeveloperName,
    String cadenceType,
    Integer intervalMinutes,
    Integer intervalHours,
    String dayOfWeek,
    Integer hourOfDay,
    Integer minuteOfHour
  ) {
    if (String.isBlank(jobConfigDeveloperName)) {
      throw new CatalogJobConfigException(
        'A Catalog Job Config developer name is required.'
      );
    }

    String normalizedCadenceType = String.isBlank(cadenceType)
      ? null
      : cadenceType.trim();
    String cronExpression;

    if (normalizedCadenceType == SCHEDULE_CADENCE_MINUTES) {
      cronExpression = CatalogProductSyncScheduler.buildMinuteCronExpression(
        intervalMinutes,
        minuteOfHour
      );
    } else if (normalizedCadenceType == SCHEDULE_CADENCE_HOURLY) {
      cronExpression = CatalogProductSyncScheduler.buildHourlyCronExpression(
        intervalHours,
        minuteOfHour
      );
    } else if (normalizedCadenceType == SCHEDULE_CADENCE_WEEKLY) {
      cronExpression = CatalogProductSyncScheduler.buildWeeklyCronExpression(
        dayOfWeek,
        hourOfDay,
        minuteOfHour
      );
    } else {
      throw new CatalogJobConfigException(
        'Supported schedule cadences are Minutes, Hourly, and Weekly.'
      );
    }

    CatalogProductSyncScheduler.upsertConfiguredSyncSchedule(
      jobConfigDeveloperName.trim(),
      cronExpression
    );

    return buildScheduleResult(jobConfigDeveloperName.trim());
  }

  /**
   * Removes the native Salesforce scheduled job for a catalog sync config.
   */
  @AuraEnabled
  public static Map<String, Object> clearCatalogJobSchedule(
    String jobConfigDeveloperName
  ) {
    if (String.isBlank(jobConfigDeveloperName)) {
      throw new CatalogJobConfigException(
        'A Catalog Job Config developer name is required.'
      );
    }

    CatalogProductSyncScheduler.clearScheduledSync(
      jobConfigDeveloperName.trim()
    );

    return buildScheduleResult(jobConfigDeveloperName.trim());
  }

  /**
   * Gets selector data used by the guided catalog job setup workspace.
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getSetupWorkspaceOptions() {
    Map<String, Object> result = new Map<String, Object>();
    result.put(
      'webStores',
      loadNamedRecordOptions(
        'WebStore',
        'SELECT Id, Name FROM WebStore ORDER BY Name LIMIT ' +
        OPTION_QUERY_LIMIT
      )
    );
    result.put(
      'productCatalogs',
      loadNamedRecordOptions(
        'ProductCatalog',
        'SELECT Id, Name FROM ProductCatalog ORDER BY Name LIMIT ' +
        OPTION_QUERY_LIMIT
      )
    );
    result.put(
      'builderTypeOptions',
      CatalogJsonBuilderFactory.getAvailableBuilderTypes()
    );
    result.put('productFieldOptions', getProductFieldOptions());
    return result;
  }

  /**
   * Builds a preflight preview for a draft catalog job configuration.
   */
  @AuraEnabled
  public static Map<String, Object> previewCatalogJobDraft(
    String label,
    String developerName,
    String coveoOrgId,
    String sourceId,
    String availabilitySourceId,
    String syncMode,
    String baselineFullConfigDeveloperName,
    String catalogId,
    String webStoreId,
    String locale,
    String builderType,
    String buyerGroupAvailabilityMode,
    String productFilter,
    List<String> additionalProductFields
  ) {
    Map<String, Object> result = new Map<String, Object>();
    List<String> validationMessages = new List<String>();
    List<String> warningMessages = new List<String>();
    Integer selectedFieldCount = additionalProductFields == null
      ? 0
      : additionalProductFields.size();
    Boolean syncModeSupported = CatalogSyncMode.isSupportedValue(syncMode);
    String resolvedSyncMode = CatalogSyncMode.resolve(syncMode);
    String normalizedBaselineFullConfigDeveloperName = String.isBlank(
        baselineFullConfigDeveloperName
      )
      ? null
      : baselineFullConfigDeveloperName.trim();
    Boolean modeSupported = CatalogBuyerGroupAvailabilityMode.isSupportedValue(
      buyerGroupAvailabilityMode
    );
    String resolvedMode = CatalogBuyerGroupAvailabilityMode.resolveDraftMode(
      buyerGroupAvailabilityMode
    );
    Boolean availabilityEnabled = CatalogBuyerGroupAvailabilityMode.isBuyerGroupAccessEnabled(
      resolvedMode
    );
    Boolean usesPairedSource = CatalogBuyerGroupAvailabilityMode.usesPairedSource(
      resolvedMode
    );
    Boolean usesEmbedded = CatalogBuyerGroupAvailabilityMode.usesEmbedded(
      resolvedMode
    );

    if (String.isBlank(label)) {
      validationMessages.add('Job label is required.');
    }
    if (String.isBlank(developerName)) {
      validationMessages.add(
        'Developer Name is required. It can be generated from the job label.'
      );
    }
    if (String.isBlank(coveoOrgId)) {
      validationMessages.add('Coveo Org Id is required.');
    }
    if (String.isBlank(sourceId)) {
      validationMessages.add('Product Source Id is required.');
    }
    if (!syncModeSupported) {
      validationMessages.add('Sync Type must be Full or Delta.');
    }
    if (String.isBlank(locale)) {
      validationMessages.add('Locale is required.');
    }
    if (!modeSupported) {
      validationMessages.add(
        'Buyer Group Availability Mode must be Disabled, PairedSource, Embedded, or DualWrite.'
      );
    }
    if (
      resolvedSyncMode == CatalogSyncMode.DELTA &&
      String.isBlank(normalizedBaselineFullConfigDeveloperName)
    ) {
      validationMessages.add(
        'Baseline Full Config Developer Name is required for Delta syncs.'
      );
    }
    if (usesPairedSource && String.isBlank(availabilitySourceId)) {
      validationMessages.add(
        'Availability Source Id is required when Buyer Group availability is enabled.'
      );
    }
    if (availabilityEnabled && String.isBlank(webStoreId)) {
      validationMessages.add(
        'Web Store is required when Buyer Group availability is enabled.'
      );
    }

    if (String.isBlank(catalogId)) {
      warningMessages.add(
        'No catalog is selected, so the product sync will use all active products that match the optional filter.'
      );
    }
    if (selectedFieldCount > 12) {
      warningMessages.add(
        'A large number of extra fields can slow down exports and increase payload size.'
      );
    }
    if (String.isBlank(builderType)) {
      warningMessages.add(
        'No Builder Type is selected, so this job will fall back to the global default builder.'
      );
    }
    if (availabilityEnabled) {
      try {
        if (
          !CatalogProductIdentityResolver.supportsBuilderDrivenIdentity(
            builderType
          )
        ) {
          warningMessages.add(
            'The selected builder does not implement ICatalogProductIdentityProvider. Buyer Group access updates will fall back to ProductCode, then Salesforce Id, and may not match a custom ec_product_id.'
          );
        }
      } catch (Exception e) {
        warningMessages.add(
          'Unable to confirm builder-driven ec_product_id support for Buyer Group access: ' +
          e.getMessage()
        );
      }
    }

    Integer estimatedProductCount = 0;
    Integer buyerGroupCount = 0;

    try {
      estimatedProductCount = getEstimatedProductCount(
        catalogId,
        productFilter
      );
      if (estimatedProductCount == 0) {
        warningMessages.add(
          'The current catalog and filter settings resolve to zero active products.'
        );
      } else if (estimatedProductCount > 10000) {
        warningMessages.add(
          'This job targets a large catalog. Consider tuning batch size and monitoring throughput before the first full sync.'
        );
      }
    } catch (Exception e) {
      validationMessages.add(
        'Unable to estimate product count: ' + e.getMessage()
      );
    }

    if (availabilityEnabled && String.isNotBlank(webStoreId)) {
      try {
        buyerGroupCount = getBuyerGroupCountForWebStore(webStoreId);
        if (buyerGroupCount == 0) {
          warningMessages.add(
            'The selected Web Store currently has no linked Buyer Groups.'
          );
        }
      } catch (Exception e) {
        validationMessages.add(
          'Unable to evaluate Buyer Group coverage: ' + e.getMessage()
        );
      }
    }

    if (
      usesEmbedded &&
      String.isNotBlank(sourceId) &&
      String.isNotBlank(webStoreId)
    ) {
      List<String> conflictingConfigs = findEmbeddedSourceConflicts(
        developerName,
        sourceId,
        webStoreId
      );
      if (!conflictingConfigs.isEmpty()) {
        warningMessages.add(
          'Embedded access shares the product source with active configs that use a different Web Store: ' +
            String.join(conflictingConfigs, ', ') +
            '.'
        );
      }
    }

    result.put('estimatedProductCount', estimatedProductCount);
    result.put('buyerGroupCount', buyerGroupCount);
    result.put('selectedFieldCount', selectedFieldCount);
    result.put('syncMode', resolvedSyncMode);
    result.put(
      'baselineFullConfigDeveloperName',
      normalizedBaselineFullConfigDeveloperName
    );
    result.put('buyerGroupAvailabilityMode', resolvedMode);
    result.put('validationMessages', validationMessages);
    result.put('warningMessages', warningMessages);
    result.put('isReady', validationMessages.isEmpty());
    return result;
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
   * Gets all available builder class options with descriptions.
   * Returns both built-in builders and any custom implementations.
   */
  @AuraEnabled(cacheable=true)
  public static List<Map<String, String>> getBuilderClassOptions() {
    List<Map<String, String>> options = new List<Map<String, String>>();

    // Map of builder types to user-friendly descriptions
    Map<String, String> builderDescriptions = new Map<String, String>{
      'CatalogJsonBuilderDefault' => 'Simple products without grouping or variant logic',
      'CatalogJsonBuilderCommerce' => 'Standard commerce with B2B category hierarchy (recommended for most use cases)',
      'CatalogJsonBuilderGrouping' => 'Product families with parent-child grouping relationships (ec_item_group_id)',
      'CatalogJsonBuilderVariant' => 'Product variants with size/color/material attributes (ec_variant_id)',
      'CatalogJsonBuilderGroupingWithVariants' => 'Combined three-tier hierarchy: Group → Product → Variant (ec_product_family + ec_item_group_id + ec_variant_id)'
    };

    // Load all builder mappings
    for (CatalogJsonBuilderMapping__mdt mapping : [
      SELECT DeveloperName, MasterLabel, ClassName__c
      FROM CatalogJsonBuilderMapping__mdt
      WHERE DeveloperName != 'Active'
      ORDER BY MasterLabel
    ]) {
      Map<String, String> option = new Map<String, String>();
      option.put('label', mapping.MasterLabel);
      option.put('value', mapping.ClassName__c);

      // Use predefined description or create a custom one
      if (builderDescriptions.containsKey(mapping.ClassName__c)) {
        option.put(
          'description',
          builderDescriptions.get(mapping.ClassName__c)
        );
      } else {
        option.put('description', 'Custom builder: ' + mapping.ClassName__c);
      }

      options.add(option);
    }

    return options;
  }

  private static List<Map<String, String>> getProductFieldOptions() {
    List<Map<String, String>> options = new List<Map<String, String>>();
    Map<String, Schema.SObjectField> fields = Product2.SObjectType.getDescribe()
      .fields.getMap();
    List<String> sortKeys = new List<String>();
    Map<String, String> apiNameBySortKey = new Map<String, String>();

    for (String apiName : fields.keySet()) {
      if (EXCLUDED_PRODUCT_FIELD_API_NAMES.contains(apiName)) {
        continue;
      }

      Schema.DescribeFieldResult describe = fields.get(apiName).getDescribe();
      if (!describe.isAccessible()) {
        continue;
      }

      String sortKey = describe.getLabel().toLowerCase() + '|' + apiName;
      sortKeys.add(sortKey);
      apiNameBySortKey.put(sortKey, apiName);
    }

    sortKeys.sort();

    for (String sortKey : sortKeys) {
      String apiName = apiNameBySortKey.get(sortKey);
      Schema.DescribeFieldResult describe = fields.get(apiName).getDescribe();

      options.add(
        new Map<String, String>{
          'value' => apiName,
          'label' => describe.getLabel() +
          ' (' +
          apiName +
          ')'
        }
      );
    }

    return options;
  }

  private static List<Map<String, String>> loadNamedRecordOptions(
    String objectApiName,
    String soql
  ) {
    List<Map<String, String>> options = new List<Map<String, String>>();
    if (!Schema.getGlobalDescribe().containsKey(objectApiName)) {
      return options;
    }

    for (SObject record : Database.query(soql)) {
      options.add(
        new Map<String, String>{
          'value' => String.valueOf(record.get('Id')),
          'label' => String.valueOf(record.get('Name')),
          'description' => String.valueOf(record.get('Id'))
        }
      );
    }

    return options;
  }

  private static Integer getEstimatedProductCount(
    String catalogId,
    String productFilter
  ) {
    String query = 'SELECT COUNT() FROM Product2 WHERE IsActive = true';

    if (String.isNotBlank(catalogId)) {
      Set<Id> productIdsInCatalog = getProductIdsForCatalog(catalogId);
      if (productIdsInCatalog.isEmpty()) {
        return 0;
      }
      query += ' AND Id IN :productIdsInCatalog';
    }

    if (String.isNotBlank(productFilter)) {
      String sanitizedFilter = validateAndSanitizeFilter(productFilter);
      query += ' AND (' + sanitizedFilter + ')';
    }

    return Database.countQuery(query);
  }

  private static Set<Id> getProductIdsForCatalog(String catalogId) {
    Set<Id> productIds = new Set<Id>();

    for (ProductCategoryProduct catalogMembership : [
      SELECT ProductId
      FROM ProductCategoryProduct
      WHERE ProductCategory.CatalogId = :catalogId AND ProductId != NULL
    ]) {
      productIds.add(catalogMembership.ProductId);
    }

    return productIds;
  }

  private static String validateAndSanitizeFilter(String filter) {
    if (String.isBlank(filter)) {
      return filter;
    }

    String trimmedFilter = filter.trim();
    String normalizedFilter = trimmedFilter.replaceAll('[\\t\\n\\r]+', ' ')
      .toUpperCase();

    List<String> dmlPatterns = new List<String>{
      'INSERT ',
      'UPDATE ',
      'DELETE ',
      'UPSERT ',
      'MERGE ',
      'UNDELETE '
    };

    for (String pattern : dmlPatterns) {
      if (normalizedFilter.contains(pattern)) {
        throw new CatalogJobException(
          'Invalid ProductFilter__c value: contains DML keyword "' +
            pattern.trim() +
            '". Only valid SOQL WHERE clause fragments are allowed.'
        );
      }
    }

    if (
      normalizedFilter.contains('SELECT ') &&
      normalizedFilter.contains(' FROM ')
    ) {
      throw new CatalogJobException(
        'Invalid ProductFilter__c value: contains subquery pattern. ' +
        'Only simple SOQL WHERE clause fragments are allowed.'
      );
    }

    return trimmedFilter;
  }

  private static Integer getBuyerGroupCountForWebStore(String webStoreId) {
    if (!Schema.getGlobalDescribe().containsKey('WebStoreBuyerGroup')) {
      return 0;
    }

    return Database.countQuery(
      'SELECT COUNT() FROM WebStoreBuyerGroup WHERE WebStoreId = :webStoreId'
    );
  }

  private static List<String> findEmbeddedSourceConflicts(
    String developerName,
    String sourceId,
    String webStoreId
  ) {
    List<String> conflictingConfigs = new List<String>();

    if (String.isBlank(sourceId) || String.isBlank(webStoreId)) {
      return conflictingConfigs;
    }

    for (CatalogJobConfig__mdt config : [
      SELECT
        DeveloperName,
        MasterLabel,
        SourceId__c,
        WebStoreId__c,
        IsActive__c,
        EnableBuyerGroupAvailability__c,
        BuyerGroupAvailabilityMode__c
      FROM CatalogJobConfig__mdt
      WHERE SourceId__c = :sourceId AND IsActive__c = TRUE
    ]) {
      if (
        config.DeveloperName == developerName ||
        !CatalogBuyerGroupAvailabilityMode.usesEmbedded(config)
      ) {
        continue;
      }

      if (
        String.isBlank(config.WebStoreId__c) ||
        config.WebStoreId__c == webStoreId
      ) {
        continue;
      }

      conflictingConfigs.add(
        config.MasterLabel + ' (' + config.WebStoreId__c + ')'
      );
    }

    return conflictingConfigs;
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

  private static Map<String, Object> buildScheduleResult(
    String jobConfigDeveloperName
  ) {
    CatalogProductSyncScheduler.ScheduleSnapshot snapshot = CatalogProductSyncScheduler.getConfiguredScheduleSnapshot(
      jobConfigDeveloperName
    );

    return new Map<String, Object>{
      'developerName' => jobConfigDeveloperName,
      'isScheduled' => snapshot == null ? false : snapshot.isScheduled,
      'scheduledJobName' => snapshot == null ? null : snapshot.jobName,
      'scheduleState' => snapshot == null ? null : snapshot.state,
      'scheduleCronExpression' => snapshot == null
        ? null
        : snapshot.cronExpression,
      'scheduleNextFireTime' => snapshot == null ? null : snapshot.nextFireTime,
      'schedulePreviousFireTime' => snapshot == null
        ? null
        : snapshot.previousFireTime,
      'scheduleTimesTriggered' => snapshot == null
        ? null
        : snapshot.timesTriggered,
      'scheduleCadenceRecognized' => snapshot == null
        ? false
        : snapshot.cadenceRecognized,
      'scheduleCadenceType' => snapshot == null ? null : snapshot.cadenceType,
      'scheduleIntervalMinutes' => snapshot == null
        ? null
        : snapshot.intervalMinutes,
      'scheduleIntervalHours' => snapshot == null
        ? null
        : snapshot.intervalHours,
      'scheduleDayOfWeek' => snapshot == null ? null : snapshot.dayOfWeek,
      'scheduleHourOfDay' => snapshot == null ? null : snapshot.hourOfDay,
      'scheduleMinuteOfHour' => snapshot == null ? null : snapshot.minuteOfHour
    };
  }
}
