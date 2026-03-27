public with sharing class CatalogJobRunner {
  private static final String PRODUCT_BATCH_CLASS = 'ProductCatalogExportBatch';
  private static final String AVAILABILITY_BATCH_CLASS =
    'BuyerGroupAvailabilityExportBatch';

  public class JobLaunchHandle {
    @AuraEnabled
    public String jobId { get; set; }

    @AuraEnabled
    public String channel { get; set; }

    @AuraEnabled
    public String label { get; set; }
  }

  public class LaunchResult {
    @AuraEnabled
    public String runKey { get; set; }

    @AuraEnabled
    public String developerName { get; set; }

    @AuraEnabled
    public String label { get; set; }

    @AuraEnabled
    public String mode { get; set; }

    @AuraEnabled
    public Boolean availabilityEnabled { get; set; }

    @AuraEnabled
    public String launchedAt { get; set; }

    @AuraEnabled
    public List<JobLaunchHandle> jobs { get; set; }
  }

  public class RunSnapshot {
    @AuraEnabled
    public String jobId { get; set; }

    @AuraEnabled
    public String channel { get; set; }

    @AuraEnabled
    public String apexClassName { get; set; }

    @AuraEnabled
    public String status { get; set; }

    @AuraEnabled
    public Integer jobItemsProcessed { get; set; }

    @AuraEnabled
    public Integer totalJobItems { get; set; }

    @AuraEnabled
    public Integer numberOfErrors { get; set; }

    @AuraEnabled
    public String extendedStatus { get; set; }

    @AuraEnabled
    public Boolean isTerminal { get; set; }

    @AuraEnabled
    public String createdDate { get; set; }

    @AuraEnabled
    public String completedDate { get; set; }
  }

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
  public static LaunchResult runSingle(String jobConfigDeveloperName) {
    CatalogJobConfig__mdt config = getConfig(jobConfigDeveloperName);
    return launchForConfig(config, true, false, 'products');
  }

  @AuraEnabled
  public static LaunchResult runSingleAvailability(String jobConfigDeveloperName) {
    CatalogJobConfig__mdt config = getConfig(jobConfigDeveloperName);
    validateAvailabilityEnabled(config);
    return launchForConfig(config, false, true, 'availability');
  }

  @AuraEnabled
  public static LaunchResult runSingleBoth(String jobConfigDeveloperName) {
    CatalogJobConfig__mdt config = getConfig(jobConfigDeveloperName);
    validateAvailabilityEnabled(config);
    return launchForConfig(config, true, true, 'both');
  }

  @AuraEnabled
  public static List<LaunchResult> runAllActive() {
    List<LaunchResult> launches = new List<LaunchResult>();
    for (CatalogJobConfig__mdt config : getActiveConfigs()) {
      launches.add(launchForConfig(config, true, false, 'products'));
    }
    return launches;
  }

  @AuraEnabled
  public static List<LaunchResult> runAllActiveAvailability() {
    List<LaunchResult> launches = new List<LaunchResult>();
    for (CatalogJobConfig__mdt config : getActiveConfigs()) {
      if (config.EnableBuyerGroupAvailability__c == true) {
        launches.add(launchForConfig(config, false, true, 'availability'));
      }
    }
    return launches;
  }

  @AuraEnabled
  public static List<LaunchResult> runAllActiveBoth() {
    List<LaunchResult> launches = new List<LaunchResult>();
    for (CatalogJobConfig__mdt config : getActiveConfigs()) {
      launches.add(
        launchForConfig(
          config,
          true,
          config.EnableBuyerGroupAvailability__c == true,
          config.EnableBuyerGroupAvailability__c == true ? 'both' : 'products'
        )
      );
    }
    return launches;
  }

  @AuraEnabled
  public static List<RunSnapshot> getRunSnapshots(List<String> jobIds) {
    if (jobIds == null || jobIds.isEmpty()) {
      return new List<RunSnapshot>();
    }

    Set<Id> validIds = new Set<Id>();
    for (String jobId : jobIds) {
      if (String.isBlank(jobId)) {
        continue;
      }

      try {
        validIds.add((Id) jobId);
      } catch (Exception e) {
        // Ignore invalid ids so the caller can keep polling the rest.
      }
    }

    if (validIds.isEmpty()) {
      return new List<RunSnapshot>();
    }

    Map<Id, AsyncApexJob> jobsById = new Map<Id, AsyncApexJob>(
      [
        SELECT
          Id,
          Status,
          JobItemsProcessed,
          TotalJobItems,
          NumberOfErrors,
          ExtendedStatus,
          CreatedDate,
          CompletedDate,
          ApexClass.Name
        FROM AsyncApexJob
        WHERE Id IN :validIds
      ]
    );

    List<RunSnapshot> snapshots = new List<RunSnapshot>();
    for (String requestedId : jobIds) {
      if (String.isBlank(requestedId)) {
        continue;
      }

      AsyncApexJob job;
      try {
        job = jobsById.get((Id) requestedId);
      } catch (Exception e) {
        job = null;
      }

      if (job == null) {
        continue;
      }

      RunSnapshot snapshot = new RunSnapshot();
      snapshot.jobId = String.valueOf(job.Id);
      snapshot.apexClassName = job.ApexClass != null ? job.ApexClass.Name : null;
      snapshot.channel = inferChannel(snapshot.apexClassName);
      snapshot.status = job.Status;
      snapshot.jobItemsProcessed = job.JobItemsProcessed;
      snapshot.totalJobItems = job.TotalJobItems;
      snapshot.numberOfErrors = job.NumberOfErrors;
      snapshot.extendedStatus = job.ExtendedStatus;
      snapshot.isTerminal = isTerminalStatus(job.Status);
      snapshot.createdDate = job.CreatedDate == null
        ? null
        : job.CreatedDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
      snapshot.completedDate = job.CompletedDate == null
        ? null
        : job.CompletedDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
      snapshots.add(snapshot);
    }

    return snapshots;
  }

  private static LaunchResult launchForConfig(
    CatalogJobConfig__mdt config,
    Boolean runProducts,
    Boolean runAvailability,
    String mode
  ) {
    LaunchResult launch = new LaunchResult();
    launch.runKey =
      config.DeveloperName +
      '-' +
      mode +
      '-' +
      String.valueOf(DateTime.now().getTime());
    launch.developerName = config.DeveloperName;
    launch.label = config.Label;
    launch.mode = mode;
    launch.availabilityEnabled = config.EnableBuyerGroupAvailability__c;
    launch.launchedAt = DateTime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    launch.jobs = new List<JobLaunchHandle>();

    if (runProducts == true) {
      launch.jobs.add(launchProductJob(config.DeveloperName));
    }

    if (runAvailability == true) {
      launch.jobs.add(launchAvailabilityJob(config.DeveloperName));
    }

    return launch;
  }

  private static JobLaunchHandle launchProductJob(String developerName) {
    ProductCatalogExportBatch batch = new ProductCatalogExportBatch(developerName);
    Id jobId = Database.executeBatch(batch, batch.getBatchSize());
    return createLaunchHandle(jobId, 'products', 'Product Sync');
  }

  private static JobLaunchHandle launchAvailabilityJob(String developerName) {
    BuyerGroupAvailabilityExportBatch batch = new BuyerGroupAvailabilityExportBatch(
      developerName
    );
    Id jobId = Database.executeBatch(batch, batch.getBatchSize());
    return createLaunchHandle(jobId, 'availability', 'Availability Sync');
  }

  private static JobLaunchHandle createLaunchHandle(
    Id jobId,
    String channel,
    String label
  ) {
    JobLaunchHandle handle = new JobLaunchHandle();
    handle.jobId = String.valueOf(jobId);
    handle.channel = channel;
    handle.label = label;
    return handle;
  }

  private static CatalogJobConfig__mdt getConfig(String jobConfigDeveloperName) {
    List<CatalogJobConfig__mdt> configs = [
      SELECT
        DeveloperName,
        Label,
        EnableBuyerGroupAvailability__c
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

  private static List<CatalogJobConfig__mdt> getActiveConfigs() {
    return [
      SELECT
        DeveloperName,
        Label,
        EnableBuyerGroupAvailability__c
      FROM CatalogJobConfig__mdt
      WHERE IsActive__c = TRUE
      ORDER BY Label
    ];
  }

  private static void validateAvailabilityEnabled(CatalogJobConfig__mdt config) {
    if (config.EnableBuyerGroupAvailability__c != true) {
      throw new CatalogJobConfigException(
        'EnableBuyerGroupAvailability__c must be true to run availability syncs for ' +
        config.Label +
        '.'
      );
    }
  }

  private static String inferChannel(String apexClassName) {
    if (apexClassName == AVAILABILITY_BATCH_CLASS) {
      return 'availability';
    }
    return 'products';
  }

  private static Boolean isTerminalStatus(String status) {
    return status == 'Completed' ||
      status == 'Failed' ||
      status == 'Aborted';
  }
}
