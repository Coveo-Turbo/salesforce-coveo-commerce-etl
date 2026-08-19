public with sharing class CatalogSyncChainQueueable implements Queueable, Database.AllowsCallouts {
  @TestVisible
  private static Boolean skipLaunchInTests = false;
  @TestVisible
  private static String lastProcessedConfigDeveloperName;
  @TestVisible
  private static String lastExpectedSyncMode;
  @TestVisible
  private static Boolean lastRunProducts;
  @TestVisible
  private static Boolean lastIncludeAvailability;
  @TestVisible
  private static List<String> lastRemainingConfigDeveloperNames;

  private List<String> pendingConfigDeveloperNames;
  private String expectedSyncMode;
  private Boolean runProducts;
  private Boolean includeAvailability;

  public CatalogSyncChainQueueable(
    List<String> configDeveloperNames,
    String syncMode,
    Boolean includeAvailability
  ) {
    this(configDeveloperNames, syncMode, true, includeAvailability);
  }

  public CatalogSyncChainQueueable(
    List<String> configDeveloperNames,
    String syncMode,
    Boolean runProducts,
    Boolean includeAvailability
  ) {
    this.pendingConfigDeveloperNames = normalizeConfigDeveloperNames(
      configDeveloperNames
    );
    this.expectedSyncMode = String.isBlank(syncMode)
      ? null
      : CatalogSyncMode.resolve(syncMode);
    this.runProducts = runProducts == true;
    this.includeAvailability = includeAvailability == true;
  }

  public void execute(QueueableContext context) {
    if (pendingConfigDeveloperNames.isEmpty()) {
      return;
    }

    String currentConfigDeveloperName = pendingConfigDeveloperNames.remove(0);
    if (Test.isRunningTest() && skipLaunchInTests) {
      lastProcessedConfigDeveloperName = currentConfigDeveloperName;
      lastExpectedSyncMode = expectedSyncMode;
      lastRunProducts = runProducts;
      lastIncludeAvailability = includeAvailability;
      lastRemainingConfigDeveloperNames = new List<String>(
        pendingConfigDeveloperNames
      );
      return;
    }

    CatalogJobRunner.runChainedConfig(
      currentConfigDeveloperName,
      expectedSyncMode,
      runProducts,
      includeAvailability
    );

    if (!pendingConfigDeveloperNames.isEmpty()) {
      System.enqueueJob(
        new CatalogSyncChainQueueable(
          pendingConfigDeveloperNames,
          expectedSyncMode,
          runProducts,
          includeAvailability
        )
      );
    }
  }

  public static List<String> normalizeConfigDeveloperNames(
    List<String> configDeveloperNames
  ) {
    List<String> normalizedNames = new List<String>();
    Set<String> seenNames = new Set<String>();

    if (configDeveloperNames == null) {
      return normalizedNames;
    }

    for (String configDeveloperName : configDeveloperNames) {
      String normalizedName = String.isBlank(configDeveloperName)
        ? null
        : configDeveloperName.trim();
      if (
        String.isNotBlank(normalizedName) && !seenNames.contains(normalizedName)
      ) {
        normalizedNames.add(normalizedName);
        seenNames.add(normalizedName);
      }
    }
    return normalizedNames;
  }
}
