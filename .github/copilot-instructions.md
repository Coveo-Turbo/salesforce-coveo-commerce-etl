# Copilot Instructions for salesforce-coveo-commerce-etl

This is a **Salesforce SFDX starter kit** for exporting enriched commerce catalog data to **Coveo Commerce** using the **Stream API**.

## Project Overview

This project provides an unmanaged Salesforce package that:
- Extracts product data from Salesforce
- Pushes data to Coveo Commerce Catalog sources via Stream API (`addOrUpdate` / `addOrMerge`)
- Supports multiple catalogs, dynamic product filters, dynamic Product2 fields, B2B Commerce category hierarchies
- Includes a Salesforce LWC admin console

## Project Structure

```
salesforce-coveo-commerce-etl/
├── force-app/main/default/
│   ├── classes/          # Apex classes (batch jobs, utilities, tests)
│   ├── lwc/              # Lightning Web Components
│   ├── customMetadata/   # Custom Metadata Type definitions
│   ├── objects/          # Custom objects and fields
│   ├── namedCredentials/ # Named Credentials for Coveo API
│   └── permissionsets/   # Permission sets
├── scripts/              # Shell scripts for org setup and data management
├── data/                 # Sample data for scratch orgs
└── config/               # Scratch org configuration
```

## Technology Stack

- **Salesforce Apex** for backend logic (API version 60.0)
- **Lightning Web Components (LWC)** for UI
- **Salesforce CLI (sf)** for deployment and org management
- **Prettier** with `prettier-plugin-apex` for code formatting

## Coding Standards

### Apex Best Practices
- Use the `SafeFieldUtil` class for fault-tolerant dynamic field access instead of direct field access
- Implement interfaces (e.g., `ICatalogJsonBuilder`) for extensibility
- Follow existing patterns in `CatalogJsonBuilderCommerce.cls` and `CatalogJsonBuilderFactory.cls`
- Include proper test coverage with mocked callouts
- Use Custom Metadata Types (`CatalogJobConfig__mdt`) for configuration

### Naming Conventions
- Apex class names: `PascalCase` (e.g., `ProductCatalogExportBatch`)
- Test classes: Add `Test` suffix (e.g., `SafeFieldUtilTest`)
- LWC component names: `camelCase` (e.g., `catalogJobConsole`)
- Custom fields for Coveo payloads: prefix with `ec_` for standard commerce fields, `sf_` for Salesforce-specific fields

### Code Formatting
- Use Prettier with the Apex plugin for formatting `.cls`, `.trigger`, and `.apex` files
- Use the LWC parser for `.html` files in `lwc/` directories

## Build & Test Commands

```bash
# Create scratch org and deploy
bash scripts/orgInit.sh

# Reset commerce data
npm run reset:data

# Format code with Prettier
npx prettier --write "**/*.{cls,trigger,apex,html,js,json}"
```

## Important Patterns

### Stream API Integration
- Use `CoveoStreamClient.cls` for all Coveo API interactions
- Support for `addOrUpdate`, `addOrMerge`, and `deleteolderthan` operations
- Handle file container uploads via S3 PUT

### Batch Processing
- `ProductCatalogExportBatch.cls` is the main batch job for catalog exports
- Batch size of 100 recommended for processing

### Category Hierarchy
- Categories use B2B Commerce's `ProductCategory` and `ProductCategoryProduct` models
- Build hierarchical paths like `["Tools", "Tools|Power Tools", "Tools|Power Tools|Drills"]`

## What Copilot Should NOT Do

- Do not modify Named Credentials or External Credentials directly (security-sensitive)
- Do not commit API keys, tokens, or secrets
- Do not remove or modify test classes without understanding coverage requirements
- Do not change Custom Metadata Type field definitions without understanding downstream impacts
