#!/usr/bin/env bash
set -e

ORG_ALIAS=${1:-ccetl}

echo "🔧 Setting up Product2 custom fields for org: $ORG_ALIAS"
echo ""

# Function to create a custom field using Tooling API
create_lookup_field() {
    local field_name=$1
    local label=$2
    local relationship_name=$3
    
    echo "Creating lookup field: $field_name..."
    
    sf data create record \
        --sobject CustomField \
        --values "FullName='Product2.$field_name' Label='$label' Type='Lookup' ReferenceTo='Product2' RelationshipName='$relationship_name' DeleteConstraint='SetNull'" \
        --target-org "$ORG_ALIAS" \
        --use-tooling-api || echo "Field $field_name may already exist or creation failed"
}

create_text_field() {
    local field_name=$1
    local label=$2
    local length=${3:-50}
    
    echo "Creating text field: $field_name..."
    
    sf data create record \
        --sobject CustomField \
        --values "FullName='Product2.$field_name' Label='$label' Type='Text' Length=$length" \
        --target-org "$ORG_ALIAS" \
        --use-tooling-api || echo "Field $field_name may already exist or creation failed"
}

echo "📋 Creating Product2 custom fields..."
echo ""

# Create lookup fields
create_lookup_field "Parent_Product__c" "Parent Product" "Child_Products"
create_lookup_field "Product_Group__c" "Product Group" "Products_in_Group"

# Create text fields
create_text_field "Type" "Type" "50"
create_text_field "Variant_Color__c" "Variant Color" "50"
create_text_field "Variant_Size__c" "Variant Size" "50"
create_text_field "Variant_Material__c" "Variant Material" "50"
create_text_field "Variant_Style__c" "Variant Style" "50"

echo ""
echo "✅ Product2 custom field setup complete!"
echo ""
echo "Note: You may need to refresh your page or reconnect to see the new fields."
