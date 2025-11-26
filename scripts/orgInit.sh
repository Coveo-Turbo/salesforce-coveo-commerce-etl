#!/usr/bin/env bash
set -euo pipefail

alias="${1:-ccetl}"

echo "➡️  Creating scratch org: $alias"
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias "$alias" \
  --set-default \
  --wait 10

echo "➡️  Deploying project source"
sf project deploy start --target-org "$alias" --ignore-conflicts

echo "➡️  Activating Standard Pricebook (required by PricebookEntry)"
# Ignore failure if already active
sf data update record \
  --sobject Pricebook2 \
  --where "IsStandard=true" \
  --values "IsActive=true" \
  --target-org "$alias" || true

echo "➡️  Importing sample Product2 data"
sf data import tree \
  --plan data/Product2-plan.json \
  --target-org "$alias" || true

echo "➡️  Seeding B2B Commerce categories and product links"
sf apex run \
  --file scripts/seedB2BCategories.apex \
  --target-org "$alias"

echo "➡️  Assigning permission set"
sf org assign permset \
  --name CoveoETL_Admin \
  --target-org "$alias"

echo "➡️  Opening org"
sf org open --target-org "$alias"
