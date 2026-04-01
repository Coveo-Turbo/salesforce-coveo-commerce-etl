@IsTest
private class SafeFieldUtilTest {
  @IsTest
  static void testSafeGet_existingField() {
    Product2 p = new Product2(
      Name = 'Test Product',
      ProductCode = 'TP-001',
      IsActive = true
    );

    // Not inserted; we just want safe access behavior
    String nameVal = SafeFieldUtil.safeGetString(p, 'Name');
    String codeVal = SafeFieldUtil.safeGetString(p, 'ProductCode');

    System.assertEquals('Test Product', nameVal, 'Name should be returned');
    System.assertEquals('TP-001', codeVal, 'ProductCode should be returned');
  }

  @IsTest
  static void testSafeGet_nonExistingField() {
    Product2 p = new Product2(Name = 'Test Product', IsActive = true);

    // Field does not exist on Product2
    Object bogus = SafeFieldUtil.safeGet(p, 'DoesNotExist__c');
    System.assertEquals(
      null,
      bogus,
      'Non-existing field should return null and not throw'
    );
  }

  @IsTest
  static void testSafeGetBoolean_andNullHandling() {
    Product2 p = new Product2(Name = 'Test Product', IsActive = true);

    Boolean isActive = SafeFieldUtil.safeGetBoolean(p, 'IsActive');
    Boolean customBool = SafeFieldUtil.safeGetBoolean(p, 'In_Stock__c'); // may not exist

    System.assertEquals(
      true,
      isActive,
      'Standard boolean field should be accessible'
    );
    // If field not present or not populated, we expect null, not exception
    System.assertEquals(
      null,
      customBool,
      'Missing or non-existent boolean should return null'
    );
  }

  @IsTest
  static void testSafeGet_withNullRecordAndEmptyField() {
    Product2 p = null;

    System.assertEquals(
      null,
      SafeFieldUtil.safeGet(p, 'Name'),
      'Null record should safely return null'
    );

    Product2 p2 = new Product2(Name = 'X');
    System.assertEquals(
      null,
      SafeFieldUtil.safeGet(p2, null),
      'Blank field API name should return null'
    );
  }

  @IsTest
  static void testSafeGet_handlesUnqueriedFieldsAndTypedHelpers() {
    Account account = new Account(Name = 'Coverage Account', AnnualRevenue = 42);
    insert account;

    Account queriedAccount = [
      SELECT Id
      FROM Account
      WHERE Id = :account.Id
    ];

    System.assertEquals(
      account.Id,
      SafeFieldUtil.safeGetId(queriedAccount, 'Id'),
      'Queried Id fields should be returned through the typed helper'
    );
    System.assertEquals(
      null,
      SafeFieldUtil.safeGetString(queriedAccount, 'Name'),
      'Unqueried fields should return null instead of surfacing SObject access exceptions'
    );

    Account inMemoryAccount = new Account(
      Name = 'Revenue Account',
      AnnualRevenue = 99
    );
    System.assertEquals(
      99,
      SafeFieldUtil.safeGetDecimal(inMemoryAccount, 'AnnualRevenue'),
      'Decimal helpers should return in-memory field values when present'
    );
  }
}
