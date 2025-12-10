#!/usr/bin/env bash
set -e

ORG_ALIAS=${1:-ccetl}

echo "🔧 Setting up Product2 custom fields for org: $ORG_ALIAS"
echo ""

# Function to check if a custom field exists
field_exists() {
    local full_name=$1
    # Query Tooling API for the field existence. We use 'set +e' temporarily 
    # to allow the 'sf' command to fail gracefully if the record is not found.
    set +e
    sf data get record \
        --sobject CustomField \
        --record-id "$full_name" \
        --target-org "$ORG_ALIAS" \
        --use-tooling-api &> /dev/null
    local exit_status=$?
    set -e
    
    if [ $exit_status -eq 0 ]; then
        return 0 # Field exists
    else
        return 1 # Field does not exist or an error occurred (like no connection)
    fi
}

# Function to create a custom lookup field using Tooling API
create_lookup_field() {
    local api_name=$1
    local label=$2
    local relationship_name=$3
    local full_name="Product2.$api_name"

    if field_exists "$full_name"; then
        echo "✅ Lookup field '$full_name' already exists. Skipping creation."
    else
        echo "Creating lookup field: $full_name..."
        
        # Corrected Metadata JSON payload for a Lookup field
        sf data create record \
            --sobject CustomField \
            --values "FullName='$full_name' Metadata='{\"label\":\"$label\",\"type\":\"Lookup\",\"referenceTo\":\"Product2\",\"relationshipName\":\"$relationship_name\",\"deleteConstraint\":\"SetNull\"}'" \
            --target-org "$ORG_ALIAS" \
            --use-tooling-api
    fi
}

# Function to create a custom text field using Tooling API
create_text_field() {
    local api_name=$1
    local label=$2
    local length=${3:-50}
    local full_name="Product2.$api_name"

    if field_exists "$full_name"; then
        echo "✅ Text field '$full_name' already exists. Skipping creation."
    else
        echo "Creating text field: $full_name..."
        sf data create record \
            --sobject CustomField \
            --values "FullName='$full_name' Metadata='{\"label\":\"$label\",\"type\":\"Text\",\"length\":$length}'" \
            --target-org "$ORG_ALIAS" \
            --use-tooling-api
    fi
}

echo "📋 Processing Product2 custom fields..."
echo ""

# Create lookup fields
create_lookup_field "Parent_Product__c" "Parent Product" "Child_Products"
create_lookup_field "Product_Group__c" "Product Group" "Products_in_Group"

# Create text fields
create_text_field "Type__c" "Type" "50"
create_text_field "Variant_Color__c" "Variant Color" "50"
create_text_field "Variant_Size__c" "Variant Size" "50"
create_text_field "Variant_Material__c" "Variant Material" "50"
create_text_field "Variant_Style__c" "Variant Style" "50"

echo ""
echo "✅ Product2 custom field setup complete!"
echo ""
