# salesforce-coveo-commerce-etl


[![Salesforce](https://img.shields.io/badge/Salesforce-Apex-blue.svg)](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/)
[![SFDX](https://img.shields.io/badge/CLI-SFDX-informational.svg)](https://developer.salesforce.com/tools/sfdxcli)
![Status](https://img.shields.io/badge/status-starter--kit-green)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](#license)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)


A Salesforce **SFDX** starter kit to extract & transform **Product** data and push it to **Coveo Commerce** via the **Stream API**. It includes Batch Apex, an extensible JSON builder (interface + factory), scratch org setup, and 4‑level category sample data for quick testing. Ships as an **unmanaged package** for easy customer adoption.


> **Docs & Schema**
> • Push & update your catalog data: https://docs.coveo.com/en/p48b0322/coveo-for-commerce/push-and-update-your-catalog-data
> • Full catalog data updates: https://docs.coveo.com/en/p4eb0129/coveo-for-commerce/full-catalog-data-updates#update-operations
> • Stream/Push API schema (local copy in repo): [/assets/schema/PushApi.json](/mnt/data/PushApi.json)


---


## Contents
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Run the Export](#run-the-export)
- [Extending the JSON Builder](#extending-the-json-builder)
- [Packaging (Unmanaged)](#packaging-unmanaged)
- [Project Structure](#project-structure)
- [License](#license)


## Features
- **Batch Apex + Scheduler** to export Product2 (+ PricebookEntry) in chunks
- **Stream API file-container flow** (create file → S3 PUT → stream update)
- **Pluggable mapping** via `ICatalogJsonBuilder` and Custom Metadata–driven factory
- **Scratch org** with **4-level** category tree + sample products
- **Named Credential** & **Remote Site Settings** templates
- **Permission Set** for admin/setup


## Prerequisites
- Salesforce CLI (SFDX)
- Dev Hub enabled (for scratch orgs)
- A Coveo **API key** with Push/Stream permissions


## Quick Start
```bash
# Clone
git clone https://github.com/Coveo-Turbo/salesforce-coveo-commerce-etl.git
cd salesforce-coveo-commerce-etl


# Create scratch org, push source, import sample data
bash scripts/orgInit.sh