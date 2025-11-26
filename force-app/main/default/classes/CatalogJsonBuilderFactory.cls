public with sharing class CatalogJsonBuilderFactory {
  public static ICatalogJsonBuilder get() {
    String className;
    try {
      // Custom Metadata mapping (type: CatalogJsonBuilderMapping__mdt, field: ClassName__c)
      CatalogJsonBuilderMapping__mdt m = [
        SELECT ClassName__c
        FROM CatalogJsonBuilderMapping__mdt
        WHERE DeveloperName = 'Active'
        LIMIT 1
      ];
      className = m.ClassName__c;
    } catch (Exception e) {
      className = 'CatalogJsonBuilderCommerce'; // default
    }
    Type t = Type.forName(className);
    if (t == null) {
      throw new AuraHandledException('Unknown builder class: ' + className);
    }
    return (ICatalogJsonBuilder) t.newInstance();
  }
}
