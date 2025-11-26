#!/usr/bin/env bash
set -euo pipefail

alias="${1:-ccetl}"

# Replace the placeholders with your real Coveo Org ID and Source ID
COVEO_ORG_ID="coveoprofessionalservicesbi4l69nl"
COVEO_SOURCE_ID="coveoprofessionalservicesbi4l69nl-vkfjrttjfkrvln7d7jcaxz2mqm"

echo "➡️  Running ETL batch against $alias"
sf apex run --file scripts/batchDemo.apex --target-org "$alias"
