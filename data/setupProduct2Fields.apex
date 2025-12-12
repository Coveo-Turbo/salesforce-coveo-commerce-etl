/**
 * Script to create custom fields on Product2 for catalog variant and grouping use cases.
 * Run this script after deploying the package to set up the required fields.
 * 
 * These fields are used by:
 * - CatalogJsonBuilderGrouping
 * - CatalogJsonBuilderVariant
 * - CatalogJsonBuilderGroupingWithVariants
 * 
 * Usage: sf apex run --file data/setupProduct2Fields.apex --target-org <alias>
 */

// Create Parent_Product__c lookup field
Schema.SObjectField parentProductField = Schema.sObjectType.Product2.fields.getMap().get('Parent_Product__c');
if (parentProductField == null) {
    System.debug('Creating Parent_Product__c field...');
    
    Metadata.CustomMetadata customField = new Metadata.CustomMetadata();
    customField.fullName = 'Product2.Parent_Product__c';
    customField.label = 'Parent Product';
    
    // Note: Field creation via Metadata API requires admin permissions
    // This script documents the fields needed but cannot create them programmatically
    // Fields must be created via:
    // 1. Setup UI
    // 2. Metadata API deployment
    // 3. Scratch org definition file
    
    System.debug('⚠️  Custom fields must be created via Setup or scratch org definition');
    System.debug('⚠️  Required fields for test data:');
    System.debug('    - Parent_Product__c (Lookup to Product2)');
    System.debug('    - Product_Group__c (Lookup to Product2)');
    System.debug('    - Type (Text, 50 chars)');
    System.debug('    - Variant_Color__c (Text, 50 chars)');
    System.debug('    - Variant_Size__c (Text, 50 chars)');
    System.debug('    - Variant_Material__c (Text, 50 chars)');
    System.debug('    - Variant_Style__c (Text, 50 chars)');
} else {
    System.debug('✅ Parent_Product__c field already exists');
}

// Check other fields
List<String> fieldsToCheck = new List<String>{
    'Product_Group__c',
    'Type',
    'Variant_Color__c',
    'Variant_Size__c',
    'Variant_Material__c',
    'Variant_Style__c'
};

for (String fieldName : fieldsToCheck) {
    Schema.SObjectField field = Schema.sObjectType.Product2.fields.getMap().get(fieldName);
    if (field != null) {
        System.debug('✅ ' + fieldName + ' field exists');
    } else {
        System.debug('❌ ' + fieldName + ' field is missing');
    }
}

System.debug('');
System.debug('Field check complete. If fields are missing, add them to your scratch org definition or create them manually.');
