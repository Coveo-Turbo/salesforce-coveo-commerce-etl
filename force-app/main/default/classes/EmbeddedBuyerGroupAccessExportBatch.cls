global with sharing class EmbeddedBuyerGroupAccessExportBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
  @TestVisible private static final Integer DEFAULT_BATCH_SIZE = 1000;
  @TestVisible private static final Integer MAX_BATCH_SIZE = 2000;

  private final CatalogJobConfig__mdt jobConfig;

  public EmbeddedBuyerGroupAccessExportBatch(String jobConfigDeveloperName) {
    this(loadJobConfig(jobConfigDeveloperName));
  }

  @TestVisible
  private EmbeddedBuyerGroupAccessExportBatch(CatalogJobConfig__mdt jobConfig) {
    if (jobConfig == null) {
      throw new CatalogJobException('Catalog job config is required.');
    }

    this.jobConfig = jobConfig;
    validateConfig();
  }

  private static CatalogJobConfig__mdt loadJobConfig(
    String jobConfigDeveloperName
  ) {
    List<CatalogJobConfig__mdt> configs = [
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
        BuilderType__c,
        CatalogId__c,
        BatchSize__c,
        EnablePayloadLogging__c,
        EnableBuyerGroupAvailability__c,
        BuyerGroupAvailabilityMode__c
      FROM CatalogJobConfig__mdt
      WHERE DeveloperName = :jobConfigDeveloperName
      LIMIT 1
    ];

    if (configs.isEmpty()) {
      throw new CatalogJobException(
        'No CatalogJobConfig__mdt record found with DeveloperName: ' +
        jobConfigDeveloperName
      );
    }

    return configs[0];
  }

  public Integer getBatchSize() {
    // Access-only syncs emit one Stream API update per batch scope. Use a much
    // larger default and floor than the full product sync to avoid burst
    // throttling on large catalogs, especially in non-production orgs.
    Integer configuredBatchSize = jobConfig.BatchSize__c == null
      ? DEFAULT_BATCH_SIZE
      : Integer.valueOf(jobConfig.BatchSize__c);
    Integer normalizedBatchSize = Math.max(
      configuredBatchSize,
      DEFAULT_BATCH_SIZE
    );
    return Math.min(normalizedBatchSize, MAX_BATCH_SIZE);
  }

  global Database.QueryLocator start(Database.BatchableContext bc) {
    ICatalogJsonBuilder builder = CatalogProductIdentityResolver.getBuilder(
      jobConfig
    );
    List<String> fields = CatalogProductIdentityResolver.getRequiredProductFields(
      builder
    );

    for (
      String fieldName : CatalogBuyerGroupAccessResolver.getRequiredProductFields(
        builder
      )
    ) {
      if (!fields.contains(fieldName)) {
        fields.add(fieldName);
      }
    }

    return CatalogJobScopeUtil.buildProductQueryLocator(jobConfig, fields, null);
  }

  global void execute(Database.BatchableContext bc, List<Product2> scope) {
    ICatalogJsonBuilder builder = CatalogProductIdentityResolver.getBuilder(
      jobConfig
    );
    Map<Id, CatalogBuyerGroupAccessSnapshot> snapshotsByProductId =
      CatalogBuyerGroupAccessResolver.resolveBuyerGroupAccess(
        jobConfig,
        scope,
        builder
      );

    String jsonPayload = EmbeddedBuyerGroupAccessPayloadBuilder.buildPartialUpdateJson(
      new List<CatalogBuyerGroupAccessSnapshot>(snapshotsByProductId.values())
    );
    CoveoPayloadValidator.Result validationResult = CoveoPayloadValidator.validate(
      jsonPayload
    );

    CoveoStreamClient client = new CoveoStreamClient(
      jobConfig.CoveoOrgId__c,
      jobConfig.SourceId__c
    );
    Map<String, Object> container = client.createFileContainer();
    client.uploadNdjson(
      (String) container.get('uploadUri'),
      (Map<String, Object>) container.get('requiredHeaders'),
      Blob.valueOf(jsonPayload)
    );
    client.streamUpdate((String) container.get('fileId'));

    if (jobConfig.EnablePayloadLogging__c == true) {
      Coveo_Payload_Log__c log = new Coveo_Payload_Log__c(
        ScopeSize__c = scope.size(),
        OperationCount__c = validationResult.operationCount,
        IsValid__c = validationResult.isValid,
        Reason__c = validationResult.reason,
        Payload__c = jsonPayload.left(32000)
      );

      System.enqueueJob(
        new CoveoPayloadLogQueueable(new List<Coveo_Payload_Log__c>{ log })
      );
    }
  }

  global void finish(Database.BatchableContext bc) {
    // Embedded access syncs only issue field-level replacements on product docs.
    // There is intentionally no deleteOlderThan cleanup phase for this batch.
  }

  private void validateConfig() {
    if (!CatalogBuyerGroupAvailabilityMode.usesEmbedded(jobConfig)) {
      throw new CatalogJobConfigException(
        'BuyerGroupAvailabilityMode__c must be Embedded or DualWrite to run EmbeddedBuyerGroupAccessExportBatch.'
      );
    }

    if (String.isBlank(jobConfig.WebStoreId__c)) {
      throw new CatalogJobConfigException(
        'WebStoreId__c is required when embedded Buyer Group access is enabled.'
      );
    }
  }
}
