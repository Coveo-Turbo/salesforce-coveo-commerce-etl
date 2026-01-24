/**
 * Test class for CoveoPayloadLogQueueable
 */
@IsTest
private class CoveoPayloadLogQueueableTest {
  /**
   * Test successful insertion of payload logs via queueable
   */
  @IsTest
  static void testExecute_insertsLogsSuccessfully() {
    // Setup: Create test log records (not inserted yet)
    List<Coveo_Payload_Log__c> logs = new List<Coveo_Payload_Log__c>();
    logs.add(
      new Coveo_Payload_Log__c(
        ScopeSize__c = 10,
        OperationCount__c = 5,
        IsValid__c = true,
        Reason__c = 'Test log 1',
        Payload__c = 'test payload 1'
      )
    );
    logs.add(
      new Coveo_Payload_Log__c(
        ScopeSize__c = 20,
        OperationCount__c = 10,
        IsValid__c = true,
        Reason__c = 'Test log 2',
        Payload__c = 'test payload 2'
      )
    );

    Test.startTest();
    // Execute: Enqueue the job
    System.enqueueJob(new CoveoPayloadLogQueueable(logs));
    Test.stopTest();

    // Verify: Logs were inserted
    List<Coveo_Payload_Log__c> insertedLogs = [
      SELECT Id, ScopeSize__c, OperationCount__c, IsValid__c, Reason__c
      FROM Coveo_Payload_Log__c
      ORDER BY ScopeSize__c
    ];

    System.assertEquals(2, insertedLogs.size(), 'Should insert 2 logs');
    System.assertEquals(
      10,
      insertedLogs[0].ScopeSize__c,
      'First log scope size'
    );
    System.assertEquals(
      20,
      insertedLogs[1].ScopeSize__c,
      'Second log scope size'
    );
    System.assertEquals(true, insertedLogs[0].IsValid__c, 'First log valid');
    System.assertEquals(true, insertedLogs[1].IsValid__c, 'Second log valid');
  }

  /**
   * Test queueable with empty list
   */
  @IsTest
  static void testExecute_handlesEmptyList() {
    List<Coveo_Payload_Log__c> logs = new List<Coveo_Payload_Log__c>();

    Test.startTest();
    // Execute: Enqueue with empty list
    System.enqueueJob(new CoveoPayloadLogQueueable(logs));
    Test.stopTest();

    // Verify: No logs inserted
    List<Coveo_Payload_Log__c> insertedLogs = [
      SELECT Id
      FROM Coveo_Payload_Log__c
    ];
    System.assertEquals(0, insertedLogs.size(), 'Should insert no logs');
  }

  /**
   * Test queueable with null list
   */
  @IsTest
  static void testExecute_handlesNullList() {
    Test.startTest();
    // Execute: Enqueue with null list
    System.enqueueJob(new CoveoPayloadLogQueueable(null));
    Test.stopTest();

    // Verify: No logs inserted, no exceptions thrown
    List<Coveo_Payload_Log__c> insertedLogs = [
      SELECT Id
      FROM Coveo_Payload_Log__c
    ];
    System.assertEquals(0, insertedLogs.size(), 'Should insert no logs');
  }

  /**
   * Test that queueable handles large payload strings without heap issues
   */
  @IsTest
  static void testExecute_handlesLargePayloads() {
    // Setup: Create log with maximum allowed payload size
    List<Coveo_Payload_Log__c> logs = new List<Coveo_Payload_Log__c>();

    // Create a 32KB payload (maximum size we store in the field)
    String largePayload = 'x'.repeat(32000);

    logs.add(
      new Coveo_Payload_Log__c(
        ScopeSize__c = 100,
        OperationCount__c = 50,
        IsValid__c = true,
        Reason__c = 'Large payload test',
        Payload__c = largePayload
      )
    );

    Test.startTest();
    // Execute: Enqueue the job
    System.enqueueJob(new CoveoPayloadLogQueueable(logs));
    Test.stopTest();

    // Verify: Log was inserted successfully
    List<Coveo_Payload_Log__c> insertedLogs = [
      SELECT Id, Payload__c
      FROM Coveo_Payload_Log__c
    ];

    System.assertEquals(1, insertedLogs.size(), 'Should insert 1 log');
    System.assertEquals(
      32000,
      insertedLogs[0].Payload__c.length(),
      'Payload should be 32KB'
    );
  }
}
