public with sharing class SafeFieldUtil {
  public static Object safeGet(SObject record, String fieldName) {
    if (record == null || String.isBlank(fieldName)) {
      return null;
    }

    // Get field describe map
    Map<String, SObjectField> fields = record.getSObjectType()
      .getDescribe()
      .fields.getMap();

    // Check case-insensitive match
    if (!fields.containsKey(fieldName)) {
      return null; // Field does NOT exist → safe return
    }

    try {
      return record.get(fields.get(fieldName));
    } catch (Exception ex) {
      // Field exists but not queried or inaccessible → return null safely
      return null;
    }
  }

  public static String safeGetString(SObject record, String fieldName) {
    return (String) safeGet(record, fieldName);
  }

  public static Decimal safeGetDecimal(SObject record, String fieldName) {
    return (Decimal) safeGet(record, fieldName);
  }

  public static Boolean safeGetBoolean(SObject record, String fieldName) {
    return (Boolean) safeGet(record, fieldName);
  }

  public static Id safeGetId(SObject record, String fieldName) {
    return (Id) safeGet(record, fieldName);
  }
}
