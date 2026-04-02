public with sharing class CoveoStreamClient {
  public String orgId;
  public String sourceId;
  public CoveoStreamClient(String orgId, String sourceId) {
    this.orgId = orgId;
    this.sourceId = sourceId;
  }

  public Map<String, Object> createFileContainer() {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:Coveo_Push/organizations/' + orgId + '/files');
    req.setMethod('POST');
    HttpResponse res = new Http().send(req);
    ensureOk(res);
    return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
  }

  public void uploadNdjson(
    String uploadUri,
    Map<String, Object> requiredHeaders,
    Blob ndjson
  ) {
    HttpRequest req = new HttpRequest();
    req.setMethod('PUT');
    req.setEndpoint(uploadUri); // presigned absolute URL (S3)
    for (String h : requiredHeaders.keySet())
      req.setHeader(h, String.valueOf(requiredHeaders.get(h)));
    req.setBodyAsBlob(ndjson);
    HttpResponse res = new Http().send(req);
    ensureOk(res);
  }

  public String streamUpdate(String fileId) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(
      'callout:Coveo_Push/organizations/' +
        orgId +
        '/sources/' +
        sourceId +
        '/stream/update?fileId=' +
        EncodingUtil.urlEncode(fileId, 'UTF-8')
    );
    req.setMethod('PUT');
    req.setHeader('Content-Type', 'application/json');
    HttpResponse res = new Http().send(req);
    ensureAccepted(res);
    return res.getBody();
  }

  @TestVisible
  private static Boolean isThrottleResponse(HttpResponse response) {
    if (response == null) {
      return false;
    }

    Integer statusCode = response.getStatusCode();
    if (statusCode == 429) {
      return true;
    }

    String body = response.getBody();
    return String.isNotBlank(body) &&
      (body.contains('ORGANIZATION_IS_THROTTLED') ||
      body.contains('STREAM_API_BURST_LIMIT_REACHED'));
  }

  @TestVisible
  private static String buildErrorMessage(HttpResponse response) {
    String message =
      'Coveo error: ' +
      response.getStatus() +
      ' ' +
      response.getBody();

    if (!isThrottleResponse(response)) {
      return message;
    }

    String retryAfter = response == null ? null : response.getHeader('Retry-After');
    if (String.isNotBlank(retryAfter)) {
      message += ' Retry after ' + retryAfter.trim() + ' seconds.';
    }

    message +=
      ' Coveo throttled this Stream API request. Reduce request frequency or increase the embedded access batch size to lower the number of /stream/update calls.';
    return message;
  }

  private void ensureOk(HttpResponse r) {
    if (r.getStatusCode() >= 300)
      throw new CalloutException(buildErrorMessage(r));
  }
  private void ensureAccepted(HttpResponse r) {
    if (r.getStatusCode() >= 400)
      throw new CalloutException(buildErrorMessage(r));
  }
}
