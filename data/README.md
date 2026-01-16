# Test Data for CatalogJsonBuilder Use Cases

This directory contains test data for different Coveo Commerce catalog organization strategies.

## Data Files Overview

### Base Data (Used by All Plans)
- **ProductCatalog.json** - Main demo catalog
- **ProductCatalog-UseCases.json** - Additional catalogs for each use case (Default, Grouping, Variant, Combined)
- **ProductCategory.json**, **ProductCategory2-4.json** - Category hierarchy for main catalog
- **ProductCategory-UseCases.json** - Categories for use case catalogs with proper parent-child relationships
- **ProductCategoryProduct.json** - Product-category associations for main catalog products
- **ProductCategoryProduct-UseCases.json** - Product-category associations for use case products
- **Pricebook2.json**, **PricebookEntry.json** - Pricing data
- **Product2.json** - Default/simple products for standard commerce use

### Use Case-Specific Product Data

#### 1. Product Grouping Use Case
**File:** `Product2-Grouping.json`
**Plan:** `commerce-plan-grouping.json`
**Builder:** `CatalogJsonBuilderGrouping`

Demonstrates product families where parent products group related child products:
- **GROUP-PWR-001**: Professional Power Tools Collection
  - SKU-GRP-DRL-001: Heavy-Duty Drill (child)
  - SKU-GRP-IMP-001: Impact Driver (child)
  - SKU-GRP-GRD-001: Angle Grinder (child)
- **GROUP-HND-001**: Master Hand Tool Set
  - SKU-GRP-SOC-001: Socket Set (child)
  - SKU-GRP-PLR-001: Pliers Set (child)

**Key Fields:**
- `Parent_Product__c`: Links child products to parent group
- Results in `ec_item_group_id` in Coveo payload

#### 2. Product Variant Use Case
**File:** `Product2-Variant.json`
**Plan:** `commerce-plan-variant.json`
**Builder:** `CatalogJsonBuilderVariant`

Demonstrates product variants with different attributes (size, color, material):
- **BASE-SHIRT-001**: Coveo Pro Work Shirt (base product)
  - SKU-SHIRT-BLU-S: Blue / Small
  - SKU-SHIRT-BLU-M: Blue / Medium
  - SKU-SHIRT-RED-S: Red / Small
  - SKU-SHIRT-RED-M: Red / Medium
- **BASE-GLOVES-001**: Coveo Work Gloves (base product)
  - SKU-GLOVE-LTH-S: Leather / Small
  - SKU-GLOVE-LTH-M: Leather / Medium
  - SKU-GLOVE-SYN-S: Synthetic / Small

**Key Fields:**
- `Type`: "Base" for parent products, "Variation" for variants
- `Parent_Product__c`: Links variants to base product
- `Variant_Color__c`, `Variant_Size__c`, `Variant_Material__c`: Variant attributes
- Results in `ec_variant_id`, `ec_variant_color`, `ec_variant_size` in Coveo payload

#### 3. Combined Grouping with Variants Use Case
**File:** `Product2-GroupingWithVariants.json`
**Plan:** `commerce-plan-grouping-with-variants.json`
**Builder:** `CatalogJsonBuilderGroupingWithVariants`

Demonstrates three-tier hierarchy: Group → Product → Variant
- **FAMILY-SAFETY-001**: Professional Safety Equipment Collection (group)
  - **PROD-HELMET-001**: Safety Helmet (product in group)
    - SKU-HELM-WHT-S: White / Small (variant)
    - SKU-HELM-WHT-M: White / Medium (variant)
    - SKU-HELM-YEL-S: Yellow / Small (variant)
  - **PROD-VEST-001**: High-Visibility Vest (product in group)
    - SKU-VEST-ORG-S: Orange / Small (variant)
    - SKU-VEST-ORG-M: Orange / Medium (variant)
    - SKU-VEST-ORG-L: Orange / Large (variant)

**Key Fields:**
- `Product_Group__c`: Links products and variants to their family/group
- `Parent_Product__c`: Links variants to their parent product
- `Type`: "Base" for products, "Variation" for variants
- `Variant_Color__c`, `Variant_Size__c`: Variant attributes
- Results in `ec_product_family`, `ec_item_group_id`, `ec_variant_id` in Coveo payload

## Import Plans

### commerce-plan.json (Default - All Use Cases)
Imports ALL test data including:
- All catalog records (main + use case catalogs)
- All product data files (Product2.json + all use case product files)
- All category associations for all catalogs
This is the comprehensive plan loaded by `scripts/orgInit.sh` and provides all test data in one import.

### commerce-plan-grouping.json
Imports grouping test data. Use for testing the Grouping builder.

### commerce-plan-variant.json
Imports variant test data. Use for testing the Variant builder.

### commerce-plan-grouping-with-variants.json
Imports combined test data. Use for testing the GroupingWithVariants builder.

## Usage Examples

### Import Grouping Test Data
```bash
sf data import tree --target-org <alias> --plan data/commerce-plan-grouping.json
```

### Import Variant Test Data
```bash
sf data import tree --target-org <alias> --plan data/commerce-plan-variant.json
```

### Import Combined Test Data
```bash
sf data import tree --target-org <alias> --plan data/commerce-plan-grouping-with-variants.json
```

## Testing CatalogJsonBuilder Implementations

After importing the appropriate test data, create a `CatalogJobConfig__mdt` record with the corresponding `BuilderType__c`:

| Use Case | BuilderType__c Value | Test Data Plan |
|----------|---------------------|----------------|
| Default | `Default` | commerce-plan.json |
| Grouping | `Grouping` | commerce-plan-grouping.json |
| Variant | `Variant` | commerce-plan-variant.json |
| Combined | `GroupingWithVariants` | commerce-plan-grouping-with-variants.json |

Then run the catalog export batch job:
```apex
Database.executeBatch(new ProductCatalogExportBatch('YourConfigName'), 100);
```

## Custom Field Requirements

For the variant and combined use cases, custom fields are required on Product2. These are automatically created when running `scripts/orgInit.sh` for scratch orgs.

### Auto-Created Fields (via setup-product2-fields.sh)
- `Parent_Product__c` (Lookup to Product2) - Links variants/children to parent products
- `Product_Group__c` (Lookup to Product2) - Links products to their family/group (combined use case)
- `Type` (Text, 50 chars) - Product type: "Base" or "Variation"
- `Variant_Color__c` (Text, 50 chars) - Variant color attribute
- `Variant_Size__c` (Text, 50 chars) - Variant size attribute
- `Variant_Material__c` (Text, 50 chars) - Variant material attribute
- `Variant_Style__c` (Text, 50 chars) - Variant style attribute

### Manual Setup (for non-scratch orgs)
If you're not using a scratch org, run the field setup script manually:
```bash
bash scripts/setup-product2-fields.sh <org-alias>
```

Alternatively, create these fields via Setup UI or deploy them via metadata.

**Note:** These fields are accessed via `SafeFieldUtil`, so the builders won't error if fields are missing, but variant/grouping data won't be exported.
