#!/usr/bin/env bash
set -euo pipefail

alias="${1:-ccetl}"

echo "➡️  Running base scratch-org setup for: $alias"
SKIP_OPEN=true bash scripts/orgInit.sh "$alias"

echo "➡️  Seeding Buyer Group availability demo data"
bash scripts/seed-buyer-group-availability.sh "$alias"

echo "➡️  Opening org"
sf org open --target-org "$alias"
