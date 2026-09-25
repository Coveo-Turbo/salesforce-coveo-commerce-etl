global with sharing class CatalogDeltaCleanupBatch implements Database.Batchable<SObject> {
  private final Id runId;

  global CatalogDeltaCleanupBatch(Id runId) {
    if (runId == null) {
      throw new CatalogJobException('A catalog delta run ID is required for cleanup.');
    }
    this.runId = runId;
  }

  global Database.QueryLocator start(Database.BatchableContext context) {
    Id currentRunId = runId;
    return Database.getQueryLocator(
      'SELECT Id FROM Catalog_Delta_Work_Item__c WHERE Run__c = :currentRunId'
    );
  }

  global void execute(Database.BatchableContext context, List<SObject> scope) {
    if (scope != null && !scope.isEmpty()) {
      delete scope;
    }
  }

  global void finish(Database.BatchableContext context) {
    Boolean succeeded = completedWithoutErrors(context);
    update new Catalog_Delta_Run__c(
      Id = runId,
      CleanupStatus__c = succeeded
        ? CatalogDeltaRunService.CLEANUP_COMPLETED
        : CatalogDeltaRunService.CLEANUP_FAILED,
      LastHeartbeatAt__c = System.now()
    );
  }

  @TestVisible
  private static Boolean completedWithoutErrors(
    Database.BatchableContext context
  ) {
    if (context == null) {
      return true;
    }
    List<AsyncApexJob> jobs = [
      SELECT Status, NumberOfErrors
      FROM AsyncApexJob
      WHERE Id = :context.getJobId()
      LIMIT 1
    ];
    return !jobs.isEmpty() &&
      jobs[0].NumberOfErrors == 0 &&
      jobs[0].Status != 'Failed' &&
      jobs[0].Status != 'Aborted';
  }
}
