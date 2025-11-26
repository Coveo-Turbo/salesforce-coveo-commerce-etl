public with sharing class CoveoDeleteOlderThan {
  /**
   * Delete all catalog items whose orderingId is lower than the given value,
   * using the Stream API deleteolderthan endpoint.
   *
   * Endpoint pattern (from schema):
   *   POST /organizations/{orgId}/sources/{sourceId}/stream/deleteolderthan/{orderingId}?queueDelay=1
   */
  public static void deleteOlderThan(
    String orgId,
    String sourceId,
    Long orderingId
  ) {
    if (orderingId == null) {
      System.debug(
        LoggingLevel.WARN,
        'CoveoDeleteOlderThan: orderingId is null. Skipping stream/deleteolderthan call.'
      );
      return;
    }

    String endpoint =
      'callout:Coveo_Push/organizations/' +
      orgId +
      '/sources/' +
      sourceId +
      '/stream/deleteolderthan/' +
      orderingId +
      '?queueDelay=5';

    HttpRequest req = new HttpRequest();
    req.setEndpoint(endpoint);
    req.setMethod('POST');

    HttpResponse res = new Http().send(req);

    Integer status = res.getStatusCode();
    if (status >= 300) {
      // Log full error body to help debugging
      System.debug(
        LoggingLevel.ERROR,
        'Coveo stream/deleteolderthan failed: ' + status + ' ' + res.getBody()
      );
      throw new CalloutException(
        'Failed to delete older items (stream/deleteolderthan): ' +
          status +
          ' ' +
          res.getBody()
      );
    }

    System.debug(
      LoggingLevel.INFO,
      'CoveoDeleteOlderThan: successfully deleted older items via stream/deleteolderthan. Response=' +
      res.getBody()
    );
  }
}
