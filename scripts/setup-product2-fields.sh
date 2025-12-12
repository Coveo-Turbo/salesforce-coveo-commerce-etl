#!/usr/bin/env bash
set -e

ORG_ALIAS=${1:-ccetl}
PERMISSION_SET_NAME="CoveoETL_Admin"

echo "🔧 Setting up Product2 custom fields for org: $ORG_ALIAS"
echo ""

# Function to check if a custom field exists using a reliable SOQL query
field_exists() {
    local full_name=$1 # e.g., 'Product2.Parent_Product__c'
    echo "   Checking existence of $full_name..."
    
    # Use sf data query against the Tooling API to reliably check for the record
    set +e # Disable exit on error for the query command
    query_result=$(sf data query \
        --query "SELECT Id FROM CustomField WHERE FullName = '$full_name'" \
        --target-org "$ORG_ALIAS" \
        --use-tooling-api \
        --json)
    exit_status=$?
    set -e # Re-enable exit on error

    if [ $exit_status -eq 0 ] && [ $(echo "$query_result" | jq '.result.totalSize') -gt 0 ]; then
        echo "   -> Field $full_name found."
        return 0 # Field exists
    else
        echo "   -> Field $full_name not found."
        return 1 # Field does not exist or query failed
    fi
}

# Function to get the ID of a Permission Set
get_permission_set_id() {
    local ps_name=$1
    set +e
    PS_ID=$(sf data query --query "SELECT Id FROM PermissionSet WHERE Name = '$ps_name'" --target-org "$ORG_ALIAS" --json | jq -r '.result.records[0].Id')
    set -e
    if [ "$PS_ID" == "null" ] || [ -z "$PS_ID" ]; then
        echo "ERROR: Permission Set '$ps_name' not found. Cannot assign FLS." >&2
        exit 1
    fi
    echo "$PS_ID"
}

# Function to assign FLS using the FieldPermissions object via standard REST API
assign_fls() {
    local field_api_name=$1
    local ps_id=$2
    local s_object_type="Product2"

    echo "   Assigning FLS for $field_api_name to Permission Set ID $ps_id..."

    # Use the standard REST API (no --use-tooling-api flag) to create a FieldPermissions record
    sf data create record \
        --sobject FieldPermissions \
        --values "ParentId='$ps_id' SobjectType='$s_object_type' Field='$s_object_type.$field_api_name' PermissionsRead=true PermissionsEdit=true" \
        --target-org "$ORG_ALIAS" &> /dev/null || echo "FLS for $field_api_name may already be assigned or failed to create."
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
    assign_fls "$api_name" "$PS_ID"
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
    assign_fls "$api_name" "$PS_ID"
}

echo "📋 Processing Product2 custom fields..."
# Get the Permission Set ID first
PS_ID=$(get_permission_set_id "$PERMISSION_SET_NAME")
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
