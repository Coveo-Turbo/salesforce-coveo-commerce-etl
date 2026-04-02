@IsTest
private class CoveoApiUtilityTest {
  private static List<HttpRequest> recordedRequests = new List<HttpRequest>();

  private class MockResponse {
    Integer statusCode;
    String status;
    String body;
    Map<String, String> headers;

    MockResponse(Integer statusCode, String status, String body) {
      this(statusCode, status, body, null);
    }

    MockResponse(
      Integer statusCode,
      String status,
      String body,
      Map<String, String> headers
    ) {
      this.statusCode = statusCode;
      this.status = status;
      this.body = body;
      this.headers = headers == null ? new Map<String, String>() : headers;
    }
  }

  private class RecordingHttpMock implements HttpCalloutMock {
    private Map<String, MockResponse> responsesByToken;

    RecordingHttpMock(Map<String, MockResponse> responsesByToken) {
      this.responsesByToken = responsesByToken;
    }

    public HttpResponse respond(HttpRequest req) {
      recordedRequests.add(req);

      for (String token : responsesByToken.keySet()) {
        if (req.getEndpoint().contains(token)) {
          MockResponse config = responsesByToken.get(token);
          HttpResponse res = new HttpResponse();
          res.setStatusCode(config.statusCode);
          res.setStatus(config.status);
          res.setBody(config.body);
          for (String headerName : config.headers.keySet()) {
            res.setHeader(headerName, config.headers.get(headerName));
          }
          return res;
        }
      }

      HttpResponse fallback = new HttpResponse();
      fallback.setStatusCode(500);
      fallback.setStatus('500 Missing Mock');
      fallback.setBody('No mock configured for endpoint: ' + req.getEndpoint());
      return fallback;
    }
  }

  @IsTest
  static void testPayloadValidator_blankAndInvalidPayloads() {
    CoveoPayloadValidator.Result blankResult = CoveoPayloadValidator.validate(
      ' '
    );
    System.assertEquals(false, blankResult.isValid);
    System.assertEquals('JSON body is blank', blankResult.reason);

    CoveoPayloadValidator.Result invalidJsonResult = CoveoPayloadValidator.validate(
      '{'
    );
    System.assertEquals(false, invalidJsonResult.isValid);
    System.assert(
      invalidJsonResult.reason.startsWith('JSON deserialization failed:'),
      'Expected JSON parsing failure message'
    );

    CoveoPayloadValidator.Result wrongRootResult = CoveoPayloadValidator.validate(
      '[]'
    );
    System.assertEquals(false, wrongRootResult.isValid);
    System.assertEquals(
      'Root must be a JSON object (Map).',
      wrongRootResult.reason
    );

    CoveoPayloadValidator.Result noOpsResult = CoveoPayloadValidator.validate(
      '{"addOrUpdate":[],"addOrMerge":[],"partialUpdate":[]}'
    );
    System.assertEquals(false, noOpsResult.isValid);
    System.assertEquals(0, noOpsResult.operationCount);
    System.assert(
      noOpsResult.reason.contains('No operations found'),
      'Expected missing operations reason'
    );
  }

  @IsTest
  static void testPayloadValidator_validPayloadCountsOperations() {
    String jsonBody =
      '{"addOrUpdate":[{"documentId":"1"},{"documentId":"2"}],"addOrMerge":[{"documentId":"3"}],"partialUpdate":[{"documentId":"4","operator":"fieldValueReplace","field":"sf_buyergroup_ids","value":["BG-1"]}]}';

    CoveoPayloadValidator.Result result = CoveoPayloadValidator.validate(
      jsonBody
    );

    System.assertEquals(true, result.isValid);
    System.assertEquals('OK', result.reason);
    System.assertEquals(4, result.operationCount);
  }

  @IsTest
  static void testStreamClientHappyPathAndDeleteOlderThan() {
    recordedRequests.clear();
    Test.setMock(
      HttpCalloutMock.class,
      new RecordingHttpMock(
        new Map<String, MockResponse>{
          '/files' => new MockResponse(
            201,
            '201 Created',
            '{"fileId":"file-123","uploadUri":"https://upload.example.com/put","requiredHeaders":{"x-amz-meta-test":"abc"}}'
          ),
          'upload.example.com' => new MockResponse(200, '200 OK', ''),
          '/stream/update' => new MockResponse(
            202,
            '202 Accepted',
            '{"orderingId":42,"streamId":"stream-123"}'
          ),
          '/deleteolderthan/' => new MockResponse(
            200,
            '200 OK',
            '{"deletedCount":3}'
          )
        }
      )
    );

    CoveoStreamClient client = new CoveoStreamClient('org-123', 'source-456');

    Test.startTest();
    Map<String, Object> container = client.createFileContainer();
    client.uploadNdjson(
      'https://upload.example.com/put',
      new Map<String, Object>{ 'x-amz-meta-test' => 'abc' },
      Blob.valueOf('{"hello":"world"}')
    );
    String updateResponse = client.streamUpdate('file id/with spaces');
    CoveoDeleteOlderThan.deleteOlderThan('org-123', 'source-456', 42L);
    CoveoDeleteOlderThan.deleteOlderThan('org-123', 'source-456', null);
    Test.stopTest();

    System.assertEquals('file-123', (String) container.get('fileId'));
    System.assertEquals(
      '{"orderingId":42,"streamId":"stream-123"}',
      updateResponse
    );
    System.assertEquals(
      4,
      recordedRequests.size(),
      'Null orderingId should not trigger a callout'
    );

    HttpRequest fileRequest = recordedRequests[0];
    System.assertEquals('POST', fileRequest.getMethod());
    System.assert(
      fileRequest.getEndpoint().contains('/organizations/org-123/files'),
      'Expected file container endpoint'
    );

    HttpRequest uploadRequest = recordedRequests[1];
    System.assertEquals('PUT', uploadRequest.getMethod());
    System.assertEquals('abc', uploadRequest.getHeader('x-amz-meta-test'));

    HttpRequest updateRequest = recordedRequests[2];
    System.assertEquals('PUT', updateRequest.getMethod());
    System.assert(
      updateRequest
        .getEndpoint()
        .contains('fileId=file+id%2Fwith+spaces'),
      'Expected encoded fileId in stream update endpoint'
    );

    HttpRequest deleteRequest = recordedRequests[3];
    System.assertEquals('POST', deleteRequest.getMethod());
    System.assert(
      deleteRequest
        .getEndpoint()
        .contains('/stream/deleteolderthan/42?queueDelay=5'),
      'Expected deleteOlderThan endpoint with queue delay'
    );
  }

  @IsTest
  static void testStreamClientAndDeleteOlderThanThrowOnErrorResponses() {
    Test.setMock(
      HttpCalloutMock.class,
      new RecordingHttpMock(
        new Map<String, MockResponse>{
          '/files' => new MockResponse(
            500,
            '500 Server Error',
            '{"message":"boom"}'
          ),
          '/stream/update' => new MockResponse(
            400,
            '400 Bad Request',
            '{"message":"bad update"}'
          ),
          '/deleteolderthan/' => new MockResponse(
            503,
            '503 Service Unavailable',
            '{"message":"retry later"}'
          )
        }
      )
    );

    CoveoStreamClient client = new CoveoStreamClient('org-123', 'source-456');

    Boolean fileContainerFailed = false;
    try {
      client.createFileContainer();
    } catch (CalloutException e) {
      fileContainerFailed = true;
      System.assert(e.getMessage().contains('500 Server Error'));
    }
    System.assertEquals(true, fileContainerFailed);

    Boolean updateFailed = false;
    try {
      client.streamUpdate('file-123');
    } catch (CalloutException e) {
      updateFailed = true;
      System.assert(e.getMessage().contains('400 Bad Request'));
    }
    System.assertEquals(true, updateFailed);

    Boolean deleteFailed = false;
    try {
      CoveoDeleteOlderThan.deleteOlderThan('org-123', 'source-456', 99L);
    } catch (CalloutException e) {
      deleteFailed = true;
      System.assert(e.getMessage().contains('retry later'));
    }
    System.assertEquals(true, deleteFailed);
  }

  @IsTest
  static void testStreamClientThrottleError_includesRetryAndBatchGuidance() {
    Test.setMock(
      HttpCalloutMock.class,
      new RecordingHttpMock(
        new Map<String, MockResponse>{
          '/stream/update' => new MockResponse(
            400,
            '400 Bad Request',
            '{"errorCode":"ORGANIZATION_IS_THROTTLED","message":"STREAM_API_BURST_LIMIT_REACHED"}',
            new Map<String, String>{ 'Retry-After' => '3' }
          )
        }
      )
    );

    CoveoStreamClient client = new CoveoStreamClient('org-123', 'source-456');

    Boolean updateFailed = false;
    try {
      client.streamUpdate('file-123');
    } catch (CalloutException e) {
      updateFailed = true;
      System.assert(
        e
          .getMessage()
          .contains('ORGANIZATION_IS_THROTTLED'),
        'The raw throttle error should remain visible in the exception message'
      );
      System.assert(
        e.getMessage().contains('Retry after 3 seconds.'),
        'Throttle errors should surface the Retry-After header when provided'
      );
      System.assert(
        e
          .getMessage()
          .contains('increase the embedded access batch size'),
        'Throttle errors should guide operators toward the safer embedded access scope size'
      );
    }
    System.assertEquals(true, updateFailed);
  }

  @IsTest
  static void testCatalogJobExceptionsPreserveMessages() {
    try {
      throw new CatalogJobException('job failure');
    } catch (CatalogJobException e) {
      System.assertEquals('job failure', e.getMessage());
    }

    try {
      throw new CatalogJobConfigException('config failure');
    } catch (CatalogJobConfigException e) {
      System.assertEquals('config failure', e.getMessage());
    }
  }
}
