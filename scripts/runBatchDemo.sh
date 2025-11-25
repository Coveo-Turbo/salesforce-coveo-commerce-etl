#!/usr/bin/env bash
alias=ccetl
# Replace with your Coveo org/source IDs in the class call below
sfdx force:apex:execute -u $alias -f - <<'APEX'
Database.executeBatch(new ProductCatalogExportBatch('YOUR_COVEO_ORG_ID','YOUR_SOURCE_ID'), 100);
APEX