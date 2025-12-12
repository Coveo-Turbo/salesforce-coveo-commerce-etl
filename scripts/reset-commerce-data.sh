#!/usr/bin/env bash
set -e

ORG_ALIAS=${1:-ccetl}
DATA_DIR="data"

echo "🔄 Resetting commerce demo data in org: $ORG_ALIAS"
echo "Data dir: $DATA_DIR"
echo

########################################
# 1) Delete junctions: ProductCategoryProduct
########################################
echo "1) Deleting ProductCategoryProduct records..."
sf data query \
  --target-org "$ORG_ALIAS" \
  --query "SELECT Id FROM ProductCategoryProduct" \
  --result-format csv > "$DATA_DIR/tmp_ProductCategoryProduct.csv" || true

sf data delete bulk \
  --target-org "$ORG_ALIAS" \
  --sobject ProductCategoryProduct \
  --file "$DATA_DIR/tmp_ProductCategoryProduct.csv" || true

########################################
# 2) Delete PricebookEntry (all demo prices)
########################################
echo "2) Deleting PricebookEntry records..."
sf data query \
  --target-org "$ORG_ALIAS" \
  --query "SELECT Id FROM PricebookEntry" \
  --result-format csv > "$DATA_DIR/tmp_PricebookEntry.csv" || true

sf data delete bulk \
  --target-org "$ORG_ALIAS" \
  --sobject PricebookEntry \
  --file "$DATA_DIR/tmp_PricebookEntry.csv" || true

########################################
# 3) Delete demo Pricebook2 (keep Standard PB)
########################################
echo "3) Deleting demo Pricebook2 records (Demo Price Book only)..."
sf data query \
  --target-org "$ORG_ALIAS" \
  --query "SELECT Id FROM Pricebook2 WHERE Name = 'Demo Price Book'" \
  --result-format csv > "$DATA_DIR/tmp_Pricebook2_Demo.csv" || true

sf data delete bulk \
  --target-org "$ORG_ALIAS" \
  --sobject Pricebook2 \
  --file "$DATA_DIR/tmp_Pricebook2_Demo.csv" || true

########################################
# 4) Delete Product2 demo products
#    (includes SKU-%, GROUP-%, BASE-%, PROD-%, FAMILY-% prefixes)
########################################
echo "4) Deleting Product2 demo products (all test data prefixes)..."
sf data query \
  --target-org "$ORG_ALIAS" \
  --query "SELECT Id FROM Product2 WHERE ProductCode LIKE 'SKU-%' OR ProductCode LIKE 'GROUP-%' OR ProductCode LIKE 'BASE-%' OR ProductCode LIKE 'PROD-%' OR ProductCode LIKE 'FAMILY-%'" \
  --result-format csv > "$DATA_DIR/tmp_Product2.csv" || true

sf data delete bulk \
  --target-org "$ORG_ALIAS" \
  --sobject Product2 \
  --file "$DATA_DIR/tmp_Product2.csv" || true

########################################
# 5) Delete ProductCategory (all test catalogs)
########################################
echo "5) Deleting ProductCategory records for test catalogs..."
sf data query \
  --target-org "$ORG_ALIAS" \
  --query "SELECT Id FROM ProductCategory WHERE Catalog.Name IN ('Demo Catalog - Simple Products', 'Grouping Catalog - Product Families', 'Variant Catalog - Product Variants', 'Combined Catalog - Grouping with Variants')" \
  --result-format csv > "$DATA_DIR/tmp_ProductCategory.csv" || true

sf data delete bulk \
  --target-org "$ORG_ALIAS" \
  --sobject ProductCategory \
  --file "$DATA_DIR/tmp_ProductCategory.csv" || true

########################################
# 6) Delete ProductCatalog (all test catalogs)
########################################
echo "6) Deleting test ProductCatalog records..."
sf data query \
  --target-org "$ORG_ALIAS" \
  --query "SELECT Id FROM ProductCatalog WHERE Name IN ('Demo Catalog - Simple Products', 'Grouping Catalog - Product Families', 'Variant Catalog - Product Variants', 'Combined Catalog - Grouping with Variants')" \
  --result-format csv > "$DATA_DIR/tmp_ProductCatalog.csv" || true

sf data delete bulk \
  --target-org "$ORG_ALIAS" \
  --sobject ProductCatalog \
  --file "$DATA_DIR/tmp_ProductCatalog.csv" || true

echo
echo "✅ Delete phase completed."
echo

########################################
# 7) Re-import data via tree plan
########################################
echo "7) Importing data from $DATA_DIR/commerce-plan.json ..."
sf data import tree \
  --target-org "$ORG_ALIAS" \
  --plan "$DATA_DIR/commerce-plan.json"

echo "✅ Tree import completed."
echo

########################################
# 8) Optional: seed prices (if using Apex script)
########################################
if [ -f "$DATA_DIR/seedPrices.apex" ]; then
  echo "8) Running seedPrices.apex..."
  sf apex run \
    --target-org "$ORG_ALIAS" \
    --file "$DATA_DIR/seedPrices.apex" || true
  echo "✅ Price seeding script executed."
  echo
else
  echo "8) Skipping seedPrices.apex (file not found)."
  echo
fi

echo "🎉 Done. Demo commerce data has been reset and re-imported for org: $ORG_ALIAS"
