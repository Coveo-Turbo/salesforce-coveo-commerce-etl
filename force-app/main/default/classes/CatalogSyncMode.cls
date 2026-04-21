public with sharing class CatalogSyncMode {
  public static final String FULL = 'Full';
  public static final String DELTA = 'Delta';

  public static String resolve(CatalogJobConfig__mdt jobConfig) {
    return resolve(jobConfig == null ? null : jobConfig.SyncMode__c);
  }

  public static String resolve(String syncMode) {
    String normalized = normalize(syncMode);
    return normalized == DELTA ? DELTA : FULL;
  }

  public static Boolean isFull(CatalogJobConfig__mdt jobConfig) {
    return isFull(jobConfig == null ? null : jobConfig.SyncMode__c);
  }

  public static Boolean isFull(String syncMode) {
    return resolve(syncMode) == FULL;
  }

  public static Boolean isDelta(CatalogJobConfig__mdt jobConfig) {
    return isDelta(jobConfig == null ? null : jobConfig.SyncMode__c);
  }

  public static Boolean isDelta(String syncMode) {
    return resolve(syncMode) == DELTA;
  }

  public static Boolean isSupportedValue(String syncMode) {
    return String.isBlank(syncMode) || normalize(syncMode) != null;
  }

  private static String normalize(String syncMode) {
    if (String.isBlank(syncMode)) {
      return null;
    }

    String normalized = syncMode.trim().toLowerCase().replaceAll('[^a-z]', '');
    if (normalized == 'delta') {
      return DELTA;
    }
    if (normalized == 'full') {
      return FULL;
    }

    return null;
  }
}
