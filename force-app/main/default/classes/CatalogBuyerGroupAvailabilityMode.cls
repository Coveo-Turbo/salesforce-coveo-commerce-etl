public with sharing class CatalogBuyerGroupAvailabilityMode {
  public static final String DISABLED = 'Disabled';
  public static final String PAIRED_SOURCE = 'PairedSource';
  public static final String EMBEDDED = 'Embedded';
  public static final String DUAL_WRITE = 'DualWrite';

  public static String resolve(CatalogJobConfig__mdt jobConfig) {
    if (jobConfig == null) {
      return DISABLED;
    }

    String normalizedMode = normalize(jobConfig.BuyerGroupAvailabilityMode__c);
    if (normalizedMode != null) {
      return normalizedMode;
    }

    return jobConfig.EnableBuyerGroupAvailability__c == true
      ? PAIRED_SOURCE
      : DISABLED;
  }

  public static String resolveDraftMode(String mode) {
    String normalizedMode = normalize(mode);
    return normalizedMode == null ? DISABLED : normalizedMode;
  }

  public static Boolean isSupportedValue(String mode) {
    return String.isBlank(mode) || normalize(mode) != null;
  }

  public static Boolean isBuyerGroupAccessEnabled(CatalogJobConfig__mdt jobConfig) {
    return isBuyerGroupAccessEnabled(resolve(jobConfig));
  }

  public static Boolean isBuyerGroupAccessEnabled(String mode) {
    return resolveDraftMode(mode) != DISABLED;
  }

  public static Boolean usesPairedSource(CatalogJobConfig__mdt jobConfig) {
    return usesPairedSource(resolve(jobConfig));
  }

  public static Boolean usesPairedSource(String mode) {
    String resolvedMode = resolveDraftMode(mode);
    return resolvedMode == PAIRED_SOURCE || resolvedMode == DUAL_WRITE;
  }

  public static Boolean usesEmbedded(CatalogJobConfig__mdt jobConfig) {
    return usesEmbedded(resolve(jobConfig));
  }

  public static Boolean usesEmbedded(String mode) {
    String resolvedMode = resolveDraftMode(mode);
    return resolvedMode == EMBEDDED || resolvedMode == DUAL_WRITE;
  }

  public static String getLabel(String mode) {
    String resolvedMode = resolveDraftMode(mode);
    if (resolvedMode == PAIRED_SOURCE) {
      return 'Paired Availability Source';
    }
    if (resolvedMode == EMBEDDED) {
      return 'Embedded On Product Documents';
    }
    if (resolvedMode == DUAL_WRITE) {
      return 'Dual Write';
    }
    return 'Disabled';
  }

  private static String normalize(String mode) {
    if (String.isBlank(mode)) {
      return null;
    }

    String normalizedMode = mode.trim().toLowerCase().replaceAll('[^a-z]', '');
    if (normalizedMode == 'disabled') {
      return DISABLED;
    }
    if (
      normalizedMode == 'pairedsource' ||
      normalizedMode == 'pairedavailabilitysource' ||
      normalizedMode == 'pairedavailability' ||
      normalizedMode == 'paired'
    ) {
      return PAIRED_SOURCE;
    }
    if (
      normalizedMode == 'embedded' ||
      normalizedMode == 'embeddedaccess' ||
      normalizedMode == 'embeddedonproductdocuments'
    ) {
      return EMBEDDED;
    }
    if (normalizedMode == 'dualwrite' || normalizedMode == 'dual') {
      return DUAL_WRITE;
    }
    return null;
  }
}
