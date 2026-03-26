# **salesforce-coveo-commerce-etl**

[![Salesforce](https://img.shields.io/badge/Salesforce-Apex-blue.svg)](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/)
[![SFDX](https://img.shields.io/badge/CLI-SFDX-informational.svg)](https://developer.salesforce.com/tools/sfdxcli)
![Status](https://img.shields.io/badge/status-starter--kit-green)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](#license)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

> **A Salesforce SFDX starter kit for exporting enriched commerce catalog data to Coveo using the Stream API.**
> Supports multiple catalogs, dynamic product filters, dynamic Product2 fields, B2B Commerce category hierarchies, and a sleek Salesforce LWC admin console.

---

# 📦 Overview

This project provides an **unlocked Salesforce package** for direct installation, plus a **metadata deployment package** for source-based deployments. It extracts product data from Salesforce and pushes it to **Coveo Commerce Catalog sources** using the **Stream API** (`addOrUpdate` / `addOrMerge`).

It includes:

* A flexible **Catalog Export Batch** implementation
* Support for **multiple Coveo catalog sources** (one per locale or market)
* Dynamic **Product2 filtering** (SOQL WHERE clause per catalog)
* Dynamic **field enrichment** via Product2 fields configured in CMDT
* Correct **Commerce payload format** (flat items, objecttype, ec_* fields)
* **Category hierarchy resolution** using B2B Commerce’s ProductCategory model
* Full **delete-older-than** cleanup via Stream API
* A modern **LWC Admin Console** for triggering jobs
* SafeFieldUtil for fault-tolerant dynamic field access
* Scratch-org scripts + seeded sample data

---


## ⚠️ Prerequisites: Salesforce B2B Commerce Dependency

This package **requires Salesforce B2B Commerce** to be enabled in the target org (Scratch Org, Sandbox, or Production).
The package references standard Commerce objects such as:

* `ProductCategory`
* `ProductCategoryProduct`
* `ProductCatalog`
* `Product2` (standard, used for products)
* `Pricebook2` / `PricebookEntry` (standard pricing structure)

Because these objects are part of **Salesforce B2B Commerce**, the following must be true:

---

### The org must have B2B Commerce licensed and enabled

To verify, check in **Setup → Object Manager** that the following objects exist:

* **ProductCategory**
* **ProductCategoryProduct**
* **ProductCatalog**

If these objects are missing, the org is **not Commerce-enabled**.











## 📥 Installation

### Current Version: 1.1.8

> **Released:** 2026-01-26
> **Package Version ID:** `04tak000000Ll5ZAAS`

### Option 1: Install via Unlocked Package (Recommended)

This library is distributed as an [Unlocked Package](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_unlocked_pkg_install_pkg.htm). You can install it directly into your Salesforce environments.

#### Install via Package Links

* **Production / Developer Org:**
  [https://login.salesforce.com/packaging/installPackage.apexp?p0=04tak000000Ll5ZAAS](https://login.salesforce.com/packaging/installPackage.apexp?p0=04tak000000Ll5ZAAS)

* **Sandbox:**
  [https://test.salesforce.com/packaging/installPackage.apexp?p0=04tak000000Ll5ZAAS](https://test.salesforce.com/packaging/installPackage.apexp?p0=04tak000000Ll5ZAAS)

#### Install Using Salesforce CLI

```bash
sf package install --package 04tak000000Ll5ZAAS --target-org <your-org-alias> --wait 10
```

#### Optional: Compile Only the Package's Apex Code

```bash
sf package install --apex-compile package --package 04tak000000Ll5ZAAS --target-org <your-org-alias> --wait 10
```

After installation, assign the permission set:

```bash
sf org assign permset --name CoveoETL_Admin --target-org <your-org-alias>
```

### Option 2: Deploy via Metadata Package

1. **Download the latest release:**
   ```bash
   curl -L -o coveo-etl.zip "https://github.com/Coveo-Turbo/salesforce-coveo-commerce-etl/releases/download/v1.1.8/salesforce-coveo-commerce-etl-v1.1.8.zip"
   unzip coveo-etl.zip -d coveo-etl
   ```

2. **Deploy to your Salesforce org:**
   ```bash
   sf project deploy start --metadata-dir coveo-etl --target-org <your-org-alias>
   ```

3. **Assign the permission set:**
   ```bash
   sf org assign permset --name CoveoETL_Admin --target-org <your-org-alias>
   ```

### Option 3: Deploy from Source

1. **Clone this repository:**
   ```bash
   git clone https://github.com/Coveo-Turbo/salesforce-coveo-commerce-etl.git
   cd salesforce-coveo-commerce-etl
   ```

2. **Deploy to your org:**
   ```bash
   sf project deploy start --target-org <your-org-alias>
   ```

3. **Assign the permission set:**
   ```bash
   sf org assign permset --name CoveoETL_Admin --target-org <your-org-alias>
   ```

### Post-Installation Setup

After installation, complete the following steps:

1. **Configure Named Credential:**
   - Navigate to **Setup → Named Credentials**
   - Create or update the `Coveo_Push` Named Credential
   - Set the URL to your Coveo Push API endpoint (e.g., `https://api.cloud.coveo.com/push/v1`)

2. **Configure External Credential with API Key:**
   - Navigate to **Setup → External Credentials**
   - Find or create `CoveoPushAuthCred`
   - Add an **Authentication Parameter** named `API_KEY` with your Coveo API Key value

3. **Configure Catalog Jobs:**
   - Go to **Setup → Custom Metadata Types → Catalog Job Configurations**
   - Create configuration records for each catalog you want to export

4. **Access the Admin Console:**
   - Navigate to `/lightning/n/Coveo_ETL_Setup` in your Salesforce org

For detailed configuration instructions, see the [Configuration](#%EF%B8%8F-configuration) section below.

---

# 🚀 Features

### 🗂️ Multi-Catalog Config

Use Custom Metadata (`CatalogJobConfig__mdt`) to define multiple catalogs:

* Coveo Org ID
* Source ID
* Locale
* **Catalog ID** (`CatalogId__c`) - Filters products to a specific ProductCatalog
* Product filters (`ProductFilter__c`) - Additional SOQL WHERE clause filters
* Additional Product2 fields (`AdditionalProductFields__c`)
* Builder Type (`BuilderType__c`) - Determines how product grouping/variants are handled
* (Optional) catalog root category

### 🔎 Per-Catalog Product Filtering

#### Filter by Salesforce ProductCatalog

Set the `CatalogId__c` field to the Salesforce ProductCatalog ID. This automatically filters products to only those associated with the catalog via ProductCategory → ProductCategoryProduct relationships:

```
CatalogId__c: a0X5g000002AbCDEAZ
```

#### Additional Dynamic Filters

Each catalog can also define its own **SOQL WHERE** clause (without the WHERE keyword) for additional filtering:

```txt
Family = 'Generators' AND Locale__c = 'en_US'
```

These filters work in combination with the CatalogId filter when both are specified.

### ➕ Dynamic Field Enrichment

Customers can specify which Product2 fields should be exported:

```
Brand__c, Color__c, Gender__c
```

These become flat metadata fields in the payload:

```json
"sf_brand__c": "Acme",
"sf_color__c": "Blue"
```

### 🏷️ Correct Commerce Payload Format

Each item sent to Coveo looks like:

```json
{
  "objecttype": "Product",
  "documentId": "product://SKU123",
  "ec_name": "GenWatt 200kW",
  "ec_product_id": "SKU123",
  "ec_category": ["Generators", "Generators|Diesel", "Generators|Diesel|200kW"],
  "ec_price": 12999.99,
  "sf_brand__c": "Coveo Power"
}
```

### 🧠 Safe Field Access

`SafeFieldUtil` prevents Apex errors:

* Missing fields → safe `null`
* Unqueried fields → safe `null`
* Dynamic enrichment support
* Org-agnostic and customer-safe

### 🌳 Full Category Hierarchy

We resolve B2B Commerce category chains:

* `ProductCategoryProduct`
* `ProductCategory`
* Parent categories up to root
* Producing arrays like:

```json
[
  "Tools",
  "Tools|Power Tools",
  "Tools|Power Tools|Drills",
  "Tools|Power Tools|Drills|Cordless"
]
```

### 🔁 Stream API Support

Supports:

* `addOrUpdate` — full updates
* `addOrMerge` — incremental updates
* `stream/deleteolderthan` — full replacement cleanup
* File container upload (S3 PUT)
* OrderingId extraction

### 🧰 LWC Admin Console

A modern Experience-enabled admin UI that:

* Lists catalog configurations
* Shows stats (# active, # inactive)
* Provides “Run All Active” and “Run” per job
* Displays dynamic fields & filters
* Styled with SLDS + custom enhancements

---

# 📁 Project Structure

```
salesforce-coveo-commerce-etl/
├── force-app/
│   ├── main/default/
│   │   ├── classes/
│   │   │   ├── ProductCatalogExportBatch.cls
│   │   │   ├── CatalogJsonBuilderCommerce.cls
│   │   │   ├── CatalogJsonBuilderDefault.cls
│   │   │   ├── CatalogJsonBuilderGrouping.cls
│   │   │   ├── CatalogJsonBuilderVariant.cls
│   │   │   ├── CatalogJsonBuilderGroupingWithVariants.cls
│   │   │   ├── ICatalogJsonBuilder.cls
│   │   │   ├── CatalogJsonBuilderFactory.cls
│   │   │   ├── SafeFieldUtil.cls
│   │   │   ├── CoveoStreamClient.cls
│   │   │   ├── CoveoDeleteOlderThan.cls
│   │   │   └── CatalogJobRunner.cls
│   │   ├── lwc/
│   │   │   └── catalogJobConsole/
│   │   ├── objects/
│   │   │   └── CatalogJobConfig__mdt/
│   │   ├── namedCredentials/
│   │   ├── remoteSiteSettings/
│   │   ├── permissionsets/
│   │   └── customMetadata/
├── data/
│   ├── commerce-plan.json
│   ├── (Other data files...).json
│   └── seedPrices.apex
├── scripts/
│   ├── orgInit.sh
│   └── reset-commerce-data.sh
└── README.md
```

---

# 🔧 Setup

## Create scratch org, push source, import sample data

```
bash scripts/orgInit.sh
```

---

# 🔧 Configuration Landing Page

After installing the package, use the **Coveo Commerce ETL Setup** page to configure your integration in three simple steps:

## Access the Configuration Page

Navigate to one of the following URLs in your Salesforce org:

* **Tab URL:** `/lightning/n/Coveo_ETL_Setup`
* **App Page URL:** `/lightning/page/setup/Coveo_Commerce_ETL_Setup`

Or search for "Coveo ETL Setup" in the App Launcher.

## Configuration Steps

### Step 1 – Connect to Coveo (Named Credential)

The setup page displays the status of the `Coveo_Push` Named Credential and provides guidance on configuring it. **The status will only show `Configured` when both the Named Credential exists AND the API_KEY authentication parameter is present.**

1. Go to **Setup → Named Credentials**
2. Find or create the `Coveo_Push` Named Credential
3. Set the **URL** to your Coveo Push API endpoint (e.g., `https://api.cloud.coveo.com/push/v1`)
4. Go to **Setup → External Credentials** and find `CoveoPushAuthCred`
5. Add an **Authentication Parameter** named `API_KEY` with your Coveo API Key value
6. Assign the permission set `CoveoETL_Admin` to grant access

Use the **Test Connection** button to verify your configuration.

### Step 2 – Configure Catalog Jobs

The setup page lists all existing `CatalogJobConfig__mdt` records and provides quick access to create or edit them via Custom Metadata Setup.

### Step 3 – Advanced Builder Settings

Select which `ICatalogJsonBuilder` implementation is active. The default is `CatalogJsonBuilderCommerce`. To use a custom builder:

1. Create an Apex class implementing `ICatalogJsonBuilder`
2. Deploy it to your org
3. Update the `CatalogJsonBuilderMapping__mdt.Active` record with your class name

---

# ⚙️ Configuration

## Create Catalog Job Configs

Go to:

**Setup → Custom Metadata Types → Catalog Job Configurations**

For each catalog, create something like:

| Field                      | Example                      |
| -------------------------- | ---------------------------- |
| Developer Name             | `EN_US_Catalog`              |
| CoveoOrgId__c              | `mycoveoorg123`              |
| SourceId__c                | `mycoveoorg123-en-us-source` |
| Locale__c                  | `en-US`                      |
| IsActive__c                | ✔                           |
| ProductFilter__c           | `Family = 'Generators'`      |
| AdditionalProductFields__c | `Brand__c, Color__c`         |

---

# ▶️ Running Jobs

## Run one catalog

```apex
Database.executeBatch(new ProductCatalogExportBatch('EN_US_Catalog'), 50);
```

> **Note**: The batch size defaults to 50 but can be configured via the `BatchSize__c` field in the `CatalogJobConfig__mdt` metadata record. Use lower values (25-50) for large `AdditionalProductFields__c` payloads to avoid Apex heap size limits.

## Run all active catalogs

```apex
CatalogJobRunner.runAllActive();
```

## From LWC Console

Open the “Catalog Job Console” app page → click **Run** or **Run All Active**.

---

# 📤 Payload Format

Each export produces a **Stream API** payload:

```json
{
  "addOrUpdate": [
    {
      "objecttype": "Product",
      "documentId": "product://SKU123",
      "ec_name": "GenWatt 200kW",
      "ec_product_id": "SKU123",
      "ec_category": [
        "Tools",
        "Tools|Power Tools",
        "Tools|Power Tools|Drills",
        "Tools|Power Tools|Drills|Cordless"
      ],
      "ec_price": 1999.99,
      "sf_brand__c": "Coveo Power"
    }
  ]
}
```

---

# 🧹 Cleanup Using Stream API

After processing all batches, `finish()` calls:

```
DELETE /stream/deleteolderthan?orderingId=XYZ
```

This ensures removed Salesforce products are also removed from the catalog.

---

# 🔒 Safe Field Access

`SafeFieldUtil` ensures field access never throws:

```apex
String url     = SafeFieldUtil.safeGetString(p, 'Product_URL__c');
String brand   = SafeFieldUtil.safeGetString(p, 'Brand__c');
Boolean stock  = SafeFieldUtil.safeGetBoolean(p, 'In_Stock__c');
String color   = SafeFieldUtil.safeGetString(p, 'Color__c');
```

---

# 🧪 Testing

Includes:

* Mocked callouts for file container / S3 / stream update
* Tests for SafeFieldUtil
* Batch test with fake Product2 + PricebookEntry
* Category hierarchy test

---

# 🎨 LWC Catalog Job Console

Located in `/force-app/main/default/lwc/catalogJobConsole`.

Features:

* Modern SLDS layout
* Stats bar (total jobs, active jobs, inactive jobs)
* Run All Active
* Row-level Run
* Display of filters, extra fields, locale, source Id
* Error panel + loading state

---

# 🛠 Extending

## CatalogJsonBuilder Implementations

This ETL supports multiple catalog organization strategies through dedicated builder implementations. You can configure each catalog to use a specific builder via the `BuilderType__c` field in `CatalogJobConfig__mdt`.

### Available Builder Types

| Builder Type | Class Name | Use Case |
|-------------|-----------|----------|
| `Default` | `CatalogJsonBuilderDefault` | Simple products without grouping/variant logic |
| `Commerce` | `CatalogJsonBuilderCommerce` | Standard commerce with B2B category hierarchy (default) |
| `Grouping` | `CatalogJsonBuilderGrouping` | Product families with parent-child grouping relationships |
| `Variant` | `CatalogJsonBuilderVariant` | Product variants (size, color, material, etc.) |
| `GroupingWithVariants` | `CatalogJsonBuilderGroupingWithVariants` | Combined grouping and variant support |

### Product Grouping Use Case

Use `CatalogJsonBuilderGrouping` when your catalog has product families where:
- Parent products represent product families/groups
- Child products reference parents via `Parent_Product__c` lookup field

**Example Payload:**
```json
{
  "objecttype": "Product",
  "documentId": "product://CHILD-SKU",
  "ec_product_id": "CHILD-SKU",
  "ec_name": "Child Product",
  "ec_item_group_id": "PARENT-SKU"
}
```

### Product Variant Use Case

Use `CatalogJsonBuilderVariant` when products have SKU-level variants:
- Variant products have `Type = 'Variation'`
- Variants reference parent via `Parent_Product__c`
- Variant attributes (color, size) stored on variant records

**Example Payload:**
```json
{
  "objecttype": "Product",
  "documentId": "product://SKU-BLUE-L",
  "ec_product_id": "SKU-BLUE-L",
  "ec_item_group_id": "PARENT-SKU",
  "ec_variant_id": "SKU-BLUE-L",
  "ec_variant_color": "Blue",
  "ec_variant_size": "Large"
}
```

### Combined Grouping + Variant Use Case

Use `CatalogJsonBuilderGroupingWithVariants` for complex three-tier hierarchies:

```
Product Group (Family)
└── Product (Group Member)
    └── Variant (SKU)
```

**Example Payload:**
```json
{
  "objecttype": "Product",
  "documentId": "product://VARIANT-SKU",
  "ec_product_id": "VARIANT-SKU",
  "ec_item_group_id": "PRODUCT-SKU",
  "ec_product_family": "GROUP-SKU",
  "ec_variant_id": "VARIANT-SKU",
  "ec_variant_color": "Blue"
}
```

### Configuring Per-Catalog Builders

Set the `BuilderType__c` field in your `CatalogJobConfig__mdt` records:

| Field | Value |
|-------|-------|
| `BuilderType__c` | `Grouping` |

Or use the full class name:

| Field | Value |
|-------|-------|
| `BuilderType__c` | `CatalogJsonBuilderGrouping` |

### Creating Custom Builders

To create a custom builder:

1. Create an Apex class implementing `ICatalogJsonBuilder`:

```apex
public class MyCustomBuilder implements ICatalogJsonBuilder {
  public String buildFullUpdateNdjson(
    List<Product2> products,
    Map<Id, PricebookEntry> pbesByProduct,
    List<String> extraFieldNames
  ) {
    // Your implementation
  }

  public String buildPartialMergeNdjson(
    Map<String, Decimal> priceBySku,
    Map<String, Boolean> inStockBySku
  ) {
    // Your implementation
  }
}
```

2. Set `BuilderType__c` to your class name in the catalog config

---

## Additional Extension Points

You can further extend this starter kit by adding:

* Per-locale pricebooks
* Field mapping UI (CMDT → ec_* target mapping)
* Apex Scheduler for nightly runs
* Custom variant attribute mappings

---

# ✨ Conclusion

This project gives you everything needed to build a **robust, flexible, enterprise-ready** Salesforce → Coveo Commerce ETL pipeline, fully aligned with:

* Coveo Stream API best practices
* Proper commerce catalog payloads
* Salesforce multi-catalog patterns
* Clean LWC UX for administrators
