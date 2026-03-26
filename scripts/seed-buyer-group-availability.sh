#!/usr/bin/env bash
set -euo pipefail

ORG_ALIAS=${1:-ccetl}

echo "➡️  Seeding Buyer Group availability demo data in org: $ORG_ALIAS"
sf apex run \
  --target-org "$ORG_ALIAS" \
  --file data/seedBuyerGroupAvailability.apex

echo
echo "Next steps:"
echo "1) Copy the printed WebStoreId into CatalogJobConfig__mdt.WebStoreId__c"
echo "2) Set CatalogJobConfig__mdt.EnableBuyerGroupAvailability__c = true"
echo "3) Set CatalogJobConfig__mdt.AvailabilitySourceId__c to your Coveo Availability source id"
echo "4) Run the availability export from the Catalog Job Console or BuyerGroupAvailabilityExportBatch"
