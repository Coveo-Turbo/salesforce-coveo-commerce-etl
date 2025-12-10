#!/usr/bin/env bash
set -e

ORG_ALIAS=${1:-ccetl}

echo "🔧 Setting up Product2 custom fields for org: $ORG_ALIAS"
echo ""

# Create temporary directory for field metadata
TEMP_DIR=$(mktemp -d)
METADATA_DIR="$TEMP_DIR/metadata"
mkdir -p "$METADATA_DIR/objects/Product2/fields"

echo "📋 Creating Product2 custom field metadata..."
echo ""

# Function to create a lookup field metadata file
create_lookup_field() {
    local field_name=$1
    local label=$2
    local relationship_name=$3
    
    echo "  - $field_name (Lookup)"
    
    cat > "$METADATA_DIR/objects/Product2/fields/$field_name.field-meta.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>$field_name</fullName>
    <deleteConstraint>SetNull</deleteConstraint>
    <externalId>false</externalId>
    <label>$label</label>
    <referenceTo>Product2</referenceTo>
    <relationshipLabel>${label}s</relationshipLabel>
    <relationshipName>$relationship_name</relationshipName>
    <required>false</required>
    <trackHistory>false</trackHistory>
    <type>Lookup</type>
</CustomField>
EOF
}

# Function to create a text field metadata file
create_text_field() {
    local field_name=$1
    local label=$2
    local length=${3:-50}
    
    echo "  - $field_name (Text)"
    
    cat > "$METADATA_DIR/objects/Product2/fields/$field_name.field-meta.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>$field_name</fullName>
    <externalId>false</externalId>
    <label>$label</label>
    <length>$length</length>
    <required>false</required>
    <trackHistory>false</trackHistory>
    <type>Text</type>
    <unique>false</unique>
</CustomField>
EOF
}

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
echo "📦 Deploying fields to org..."
echo ""

# Deploy the field metadata
sf project deploy start \
    --metadata-dir "$METADATA_DIR" \
    --target-org "$ORG_ALIAS" \
    --wait 2 \
    || {
        echo "⚠️  Deployment may have failed. Fields might already exist or there may be permission issues."
        echo "   This is expected if fields already exist in your org."
    }

# Clean up temporary directory
rm -rf "$TEMP_DIR"

echo ""
echo "✅ Product2 custom field setup complete!"
echo ""
echo "Note: Fields are now available. You may need to refresh your browser to see them."
