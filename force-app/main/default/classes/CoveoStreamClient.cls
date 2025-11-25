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

  private void ensureOk(HttpResponse r) {
    if (r.getStatusCode() >= 300)
      throw new CalloutException(
        'Coveo error: ' + r.getStatus() + ' ' + r.getBody()
      );
  }
  private void ensureAccepted(HttpResponse r) {
    if (r.getStatusCode() >= 400)
      throw new CalloutException(
        'Coveo error: ' + r.getStatus() + ' ' + r.getBody()
      );
  }
}
