public with sharing class CoveoPayloadValidator {
  public class Result {
    public Boolean isValid;
    public String reason;
    public Integer operationCount;
  }

  public static Result validate(String jsonBody) {
    Result r = new Result();
    r.isValid = false;
    r.reason = 'Unknown error';
    r.operationCount = 0;

    if (String.isBlank(jsonBody)) {
      r.reason = 'JSON body is blank';
      return r;
    }

    Object rootObj;
    try {
      rootObj = JSON.deserializeUntyped(jsonBody);
    } catch (Exception e) {
      r.reason = 'JSON deserialization failed: ' + e.getMessage();
      return r;
    }

    if (!(rootObj instanceof Map<String, Object>)) {
      r.reason = 'Root must be a JSON object (Map).';
      return r;
    }

    Map<String, Object> root = (Map<String, Object>) rootObj;

    // Per commerce docs: full = addOrUpdate; partial = addOrMerge.
    List<String> opKeys = new List<String>{ 'addOrUpdate', 'addOrMerge' };

    Integer count = 0;
    for (String key : opKeys) {
      if (root.containsKey(key)) {
        Object v = root.get(key);
        if (v instanceof List<Object>) {
          count += ((List<Object>) v).size();
        }
      }
    }

    if (count == 0) {
      r.reason = 'No operations found in JSON: no non-empty addOrUpdate/addOrMerge arrays.';
      r.operationCount = 0;
      return r;
    }

    r.isValid = true;
    r.reason = 'OK';
    r.operationCount = count;
    return r;
  }
}
