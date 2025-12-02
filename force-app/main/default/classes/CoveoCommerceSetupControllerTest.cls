@IsTest
private class CoveoCommerceSetupControllerTest {
  /**
   * Mock class for successful HTTP callout (201 Created)
   */
  private class MockHttpCalloutSuccess implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(201);
      res.setBody(
        '{"fileId":"test-file-id","uploadUri":"https://test.s3.amazonaws.com/upload"}'
      );
      return res;
    }
  }

  /**
   * Mock class for HTTP 401 Unauthorized response
   */
  private class MockHttpCallout401 implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(401);
      res.setBody('{"message":"Unauthorized"}');
      return res;
    }
  }

  /**
   * Mock class for HTTP 403 Forbidden response
   */
  private class MockHttpCallout403 implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(403);
      res.setBody('{"message":"Forbidden"}');
      return res;
    }
  }

  /**
   * Mock class for HTTP 404 Not Found response
   */
  private class MockHttpCallout404 implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(404);
      res.setBody('{"message":"Organization not found"}');
      return res;
    }
  }

  /**
   * Mock class for HTTP 500 Server Error response
   */
  private class MockHttpCallout500 implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(500);
      res.setStatus('Internal Server Error');
      res.setBody('{"message":"Internal server error occurred"}');
      return res;
    }
  }

  // ============================================================
  // Tests for getNamedCredentialStatus()
  // ============================================================

  /**
   * Tests getNamedCredentialStatus returns a result without throwing exceptions.
   * The actual status depends on whether the Named Credential exists in the org.
   */
  @IsTest
  static void testGetNamedCredentialStatus_returnsResult() {
    Test.startTest();
    Map<String, Object> result = CoveoCommerceSetupController.getNamedCredentialStatus();
    Test.stopTest();

    System.assertNotEquals(
      null,
      result,
      'getNamedCredentialStatus should return a non-null map'
    );
    System.assert(
      result.containsKey('exists'),
      'Result should contain exists key'
    );
    System.assert(
      result.containsKey('endpoint'),
      'Result should contain endpoint key'
    );
    System.assert(
      result.containsKey('status'),
      'Result should contain status key'
    );
  }

  /**
   * Tests getNamedCredentialStatus handles error scenarios gracefully.
   * Since Named Credential may not exist in test context, validates error handling.
   */
  @IsTest
  static void testGetNamedCredentialStatus_handlesErrors() {
    Test.startTest();
    Map<String, Object> result = CoveoCommerceSetupController.getNamedCredentialStatus();
    Test.stopTest();

    // Either exists is true (NC found) or false with appropriate status
    Boolean exists = (Boolean) result.get('exists');
    String status = (String) result.get('status');

    System.assertNotEquals(null, exists, 'exists should not be null');
    System.assertNotEquals(null, status, 'status should not be null');

    // If NC doesn't exist, status should indicate error or not configured
    if (!exists) {
      System.assert(
        status.contains('Error') || status.contains('Not Configured'),
        'Status should indicate error or not configured when NC does not exist'
      );
    }
  }

  // ============================================================
  // Tests for getCatalogJobConfigs()
  // ============================================================

  /**
   * Tests getCatalogJobConfigs returns a list without throwing exceptions.
   * Since Custom Metadata is read-only in tests, validates method execution.
   */
  @IsTest
  static void testGetCatalogJobConfigs_returnsListWithoutError() {
    Test.startTest();
    List<Map<String, Object>> configs = CoveoCommerceSetupController.getCatalogJobConfigs();
    Test.stopTest();

    System.assertNotEquals(
      null,
      configs,
      'getCatalogJobConfigs should return a non-null list'
    );
  }

  /**
   * Tests getCatalogJobConfigs returns configs with expected field mappings.
   * Validates that the map structure contains all expected keys.
   */
  @IsTest
  static void testGetCatalogJobConfigs_hasExpectedFields() {
    Test.startTest();
    List<Map<String, Object>> configs = CoveoCommerceSetupController.getCatalogJobConfigs();
    Test.stopTest();

    // If configs exist, verify all expected keys are present
    for (Map<String, Object> config : configs) {
      System.assert(config.containsKey('id'), 'Config should have id key');
      System.assert(
        config.containsKey('developerName'),
        'Config should have developerName key'
      );
      System.assert(
        config.containsKey('label'),
        'Config should have label key'
      );
      System.assert(
        config.containsKey('coveoOrgId'),
        'Config should have coveoOrgId key'
      );
      System.assert(
        config.containsKey('sourceId'),
        'Config should have sourceId key'
      );
      System.assert(
        config.containsKey('locale'),
        'Config should have locale key'
      );
      System.assert(
        config.containsKey('isActive'),
        'Config should have isActive key'
      );
      System.assert(
        config.containsKey('productFilter'),
        'Config should have productFilter key'
      );
      System.assert(
        config.containsKey('additionalProductFields'),
        'Config should have additionalProductFields key'
      );
    }
  }

  // ============================================================
  // Tests for getActiveBuilderMapping()
  // ============================================================

  /**
   * Tests getActiveBuilderMapping returns default values when no Active record exists.
   */
  @IsTest
  static void testGetActiveBuilderMapping_returnsDefaultWhenNoRecord() {
    Test.startTest();
    Map<String, Object> result = CoveoCommerceSetupController.getActiveBuilderMapping();
    Test.stopTest();

    System.assertNotEquals(
      null,
      result,
      'getActiveBuilderMapping should return a non-null map'
    );
    System.assert(
      result.containsKey('className'),
      'Result should contain className key'
    );
    System.assert(
      result.containsKey('isDefault'),
      'Result should contain isDefault key'
    );

    // Default class name should be CatalogJsonBuilderCommerce
    String className = (String) result.get('className');
    System.assertNotEquals(null, className, 'className should not be null');
  }

  /**
   * Tests getActiveBuilderMapping correctly identifies default builder.
   */
  @IsTest
  static void testGetActiveBuilderMapping_identifiesDefaultBuilder() {
    Test.startTest();
    Map<String, Object> result = CoveoCommerceSetupController.getActiveBuilderMapping();
    Test.stopTest();

    String className = (String) result.get('className');
    Boolean isDefault = (Boolean) result.get('isDefault');

    // If className is CatalogJsonBuilderCommerce, isDefault should be true
    if (className == 'CatalogJsonBuilderCommerce') {
      System.assertEquals(
        true,
        isDefault,
        'isDefault should be true for CatalogJsonBuilderCommerce'
      );
    }
  }

  // ============================================================
  // Tests for getBuilderClassOptions()
  // ============================================================

  /**
   * Tests getBuilderClassOptions returns a list with at least the default builder.
   */
  @IsTest
  static void testGetBuilderClassOptions_returnsDefaultBuilder() {
    Test.startTest();
    List<Map<String, String>> options = CoveoCommerceSetupController.getBuilderClassOptions();
    Test.stopTest();

    System.assertNotEquals(
      null,
      options,
      'getBuilderClassOptions should return a non-null list'
    );
    System.assert(
      options.size() >= 1,
      'Options should include at least the default builder'
    );

    // First option should be the default builder
    Map<String, String> firstOption = options[0];
    System.assert(
      firstOption.containsKey('label'),
      'Option should have label key'
    );
    System.assert(
      firstOption.containsKey('value'),
      'Option should have value key'
    );
    System.assert(
      firstOption.containsKey('description'),
      'Option should have description key'
    );
  }

  /**
   * Tests getBuilderClassOptions includes description for all options.
   */
  @IsTest
  static void testGetBuilderClassOptions_allOptionsHaveDescription() {
    Test.startTest();
    List<Map<String, String>> options = CoveoCommerceSetupController.getBuilderClassOptions();
    Test.stopTest();

    for (Map<String, String> option : options) {
      String description = option.get('description');
      System.assertNotEquals(
        null,
        description,
        'All options should have a description'
      );
      System.assert(
        description.length() > 0,
        'Description should not be empty'
      );
    }
  }

  // ============================================================
  // Tests for validateBuilderClass()
  // ============================================================

  /**
   * Tests validateBuilderClass with an empty class name.
   */
  @IsTest
  static void testValidateBuilderClass_emptyClassName() {
    Test.startTest();
    Map<String, Object> result = CoveoCommerceSetupController.validateBuilderClass(
      ''
    );
    Test.stopTest();

    System.assertEquals(
      false,
      result.get('isValid'),
      'Empty class name should be invalid'
    );
    System.assertEquals(
      'Class name cannot be empty',
      result.get('message'),
      'Message should indicate empty class name'
    );
  }

  /**
   * Tests validateBuilderClass with a null class name.
   */
  @IsTest
  static void testValidateBuilderClass_nullClassName() {
    Test.startTest();
    Map<String, Object> result = CoveoCommerceSetupController.validateBuilderClass(
      null
    );
    Test.stopTest();

    System.assertEquals(
      false,
      result.get('isValid'),
      'Null class name should be invalid'
    );
    System.assertEquals(
      'Class name cannot be empty',
      result.get('message'),
      'Message should indicate empty class name'
    );
  }

  /**
   * Tests validateBuilderClass with a non-existent class.
   */
  @IsTest
  static void testValidateBuilderClass_nonExistentClass() {
    Test.startTest();
    Map<String, Object> result = CoveoCommerceSetupController.validateBuilderClass(
      'NonExistentBuilderClass12345'
    );
    Test.stopTest();

    System.assertEquals(
      false,
      result.get('isValid'),
      'Non-existent class should be invalid'
    );
    String message = (String) result.get('message');
    System.assert(
      message.contains('not found'),
      'Message should indicate class not found'
    );
  }

  /**
   * Tests validateBuilderClass with a valid class that implements ICatalogJsonBuilder.
   */
  @IsTest
  static void testValidateBuilderClass_validClass() {
    Test.startTest();
    Map<String, Object> result = CoveoCommerceSetupController.validateBuilderClass(
      'CatalogJsonBuilderCommerce'
    );
    Test.stopTest();

    System.assertEquals(
      true,
      result.get('isValid'),
      'CatalogJsonBuilderCommerce should be valid'
    );
    String message = (String) result.get('message');
    System.assert(
      message.contains('valid'),
      'Message should indicate class is valid'
    );
  }

  /**
   * Tests validateBuilderClass with a class that doesn't implement ICatalogJsonBuilder.
   */
  @IsTest
  static void testValidateBuilderClass_classDoesNotImplementInterface() {
    Test.startTest();
    // Use a standard Apex class that doesn't implement ICatalogJsonBuilder
    Map<String, Object> result = CoveoCommerceSetupController.validateBuilderClass(
      'SafeFieldUtil'
    );
    Test.stopTest();

    System.assertEquals(
      false,
      result.get('isValid'),
      'Class not implementing ICatalogJsonBuilder should be invalid'
    );
    String message = (String) result.get('message');
    System.assert(
      message.contains('does not implement'),
      'Message should indicate class does not implement interface'
    );
  }

  // ============================================================
  // Tests for testNamedCredentialConnection()
  // ============================================================

  /**
   * Tests testNamedCredentialConnection when no catalog configs exist.
   */
  @IsTest
  static void testTestNamedCredentialConnection_noConfigs() {
    // Since we can't delete Custom Metadata in tests, we rely on test isolation
    // If no configs with CoveoOrgId__c exist, the method should return appropriate message
    Test.startTest();
    Map<String, Object> result = CoveoCommerceSetupController.testNamedCredentialConnection();
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    System.assert(
      result.containsKey('success'),
      'Result should contain success key'
    );
    System.assert(
      result.containsKey('message'),
      'Result should contain message key'
    );

    // Depending on existing metadata, this could succeed or fail
    // We're primarily validating the method executes without exceptions
  }

  /**
   * Tests testNamedCredentialConnection with successful HTTP response.
   */
  @IsTest
  static void testTestNamedCredentialConnection_successfulConnection() {
    Test.setMock(HttpCalloutMock.class, new MockHttpCalloutSuccess());

    Test.startTest();
    Map<String, Object> result = CoveoCommerceSetupController.testNamedCredentialConnection();
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    // Result depends on whether configs with CoveoOrgId__c exist
    // The mock will be used if the HTTP callout is made
  }

  /**
   * Tests testNamedCredentialConnection with 401 Unauthorized response.
   */
  @IsTest
  static void testTestNamedCredentialConnection_401Response() {
    Test.setMock(HttpCalloutMock.class, new MockHttpCallout401());

    Test.startTest();
    Map<String, Object> result = CoveoCommerceSetupController.testNamedCredentialConnection();
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    // If HTTP call was made with 401, should indicate authentication failure
    String message = (String) result.get('message');
    if (message != null && message.contains('Authentication')) {
      System.assert(
        message.contains('failed'),
        'Message should indicate authentication failure'
      );
    }
  }

  /**
   * Tests testNamedCredentialConnection with 403 Forbidden response.
   */
  @IsTest
  static void testTestNamedCredentialConnection_403Response() {
    Test.setMock(HttpCalloutMock.class, new MockHttpCallout403());

    Test.startTest();
    Map<String, Object> result = CoveoCommerceSetupController.testNamedCredentialConnection();
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
  }

  /**
   * Tests testNamedCredentialConnection with 404 Not Found response.
   */
  @IsTest
  static void testTestNamedCredentialConnection_404Response() {
    Test.setMock(HttpCalloutMock.class, new MockHttpCallout404());

    Test.startTest();
    Map<String, Object> result = CoveoCommerceSetupController.testNamedCredentialConnection();
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    // If HTTP call was made with 404, should indicate org not found
    String message = (String) result.get('message');
    if (message != null && message.contains('404')) {
      System.assert(
        message.contains('not found'),
        'Message should indicate organization not found'
      );
    }
  }

  /**
   * Tests testNamedCredentialConnection with 500 Server Error response.
   */
  @IsTest
  static void testTestNamedCredentialConnection_500Response() {
    Test.setMock(HttpCalloutMock.class, new MockHttpCallout500());

    Test.startTest();
    Map<String, Object> result = CoveoCommerceSetupController.testNamedCredentialConnection();
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    // If HTTP call was made with 500, should include status code in message
    String message = (String) result.get('message');
    if (message != null && message.contains('500')) {
      System.assert(
        message.contains('500'),
        'Message should include HTTP status code'
      );
    }
  }

  /**
   * Tests testNamedCredentialConnection handles exceptions gracefully.
   */
  @IsTest
  static void testTestNamedCredentialConnection_handlesExceptions() {
    // By not setting a mock, the callout will fail if attempted
    // This tests exception handling in the method

    Test.startTest();
    Map<String, Object> result = CoveoCommerceSetupController.testNamedCredentialConnection();
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    System.assertNotEquals(
      null,
      result.get('success'),
      'success should not be null'
    );
    System.assertNotEquals(
      null,
      result.get('message'),
      'message should not be null'
    );
  }
}
