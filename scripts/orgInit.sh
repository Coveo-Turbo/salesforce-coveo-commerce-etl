#!/usr/bin/env bash
set -euo pipefail
alias=ccetl


sfdx force:org:create -f config/project-scratch-def.json -s -a $alias
sfdx force:source:push -u $alias
# Enable Standard Pricebook (required by PricebookEntry)
sfdx force:data:record:update -s Pricebook2 -w "IsStandard=true" -v "IsActive=true" -u $alias || true
# Import sample data
# sfdx force:data:tree:import -p data/Category__c-plan.json -u $alias
# sfdx force:data:tree:import -p data/Product2-plan.json -u $alias
# Seed B2B Commerce category tree & links (ProductCategory/ProductCategoryProduct)
sfdx force:apex:execute -u $alias -f scripts/seedB2BCategories.apex
# Assign permission set
sfdx force:user:permset:assign -n CoveoETL_Admin -u $alias
# Open org
sfdx force:org:open -u $alias