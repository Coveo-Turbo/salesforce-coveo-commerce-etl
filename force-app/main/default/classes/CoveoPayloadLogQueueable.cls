/**
 * Queueable Apex class for inserting Coveo_Payload_Log__c records asynchronously.
 * This class isolates DML operations into a separate transaction, avoiding mixed DML
 * exceptions and preventing heap size issues from accumulating logs in batch state.
 *
 * Usage:
 *   List<Coveo_Payload_Log__c> logs = new List<Coveo_Payload_Log__c>();
 *   // ... populate logs
 *   System.enqueueJob(new CoveoPayloadLogQueueable(logs));
 */
public class CoveoPayloadLogQueueable implements Queueable {
  private List<Coveo_Payload_Log__c> logs;

  /**
   * Constructor
   * @param logs List of payload log records to insert
   */
  public CoveoPayloadLogQueueable(List<Coveo_Payload_Log__c> logs) {
    this.logs = logs;
  }

  /**
   * Executes the queueable job, inserting all payload logs
   * @param context QueueableContext provided by the platform
   */
  public void execute(QueueableContext context) {
    if (logs != null && !logs.isEmpty()) {
      try {
        insert logs;
        System.debug(
          LoggingLevel.INFO,
          'Successfully inserted ' + logs.size() + ' payload log(s)'
        );
      } catch (DmlException e) {
        System.debug(
          LoggingLevel.WARN,
          'Failed to insert payload logs: ' + e.getMessage()
        );
      }
    }
  }
}
