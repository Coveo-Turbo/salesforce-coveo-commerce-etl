#!/usr/bin/env bash
# Create and setup scratch org
sfdx force:org:create -f config/project-scratch-def.json -s -a coveo_etl_demo
sfdx force:source:push
