# Implementation Plan: Multi-Store Shared Catalog (Option C Hybrid)

> **Branch:** `feature/multi-store-shared-catalog`  
> **Base:** `main` @ `v1.3.3` (`d3f2739`)  
> **Date:** 2026-08-11
> **Implementation branch:** `feature/option-c-hybrid`

## Implementation Status

Option C is implemented and validated in a B2B scratch org. Multi-pricebook resolution, backward-compatible raw keys for all scoped prices, multi-store paired availability, chained scheduling, setup/run-center exposure, metadata, and permission updates are complete. Existing blank-scope price behavior and singular `WebStoreId__c` availability remain backward-compatible.

One planned UI item is intentionally deferred: chain membership is serialized in the scheduled Apex instance, but there is no persistent chain-definition metadata object. The setup UI can create and remove a chain from its current draft but cannot reconstruct membership or display durable chain progress after reload. Queueable chaining is launch-sequential rather than batch-completion-sequential.

---

## Goal

Allow a single `CatalogJobConfig__mdt` record to export one shared product catalog to Coveo with prices resolved from **multiple web-store-specific pricebooks**. Additionally, introduce chained scheduling so remaining multi-config scenarios (availability exports, etc.) consume a single Salesforce scheduled job slot instead of N slots.

This addresses the customer's Salesforce **100 scheduled Apex job limit** by collapsing N-per-store configs into fewer shared-catalog configs.

---

## Current State (Baseline)

| Aspect               | Today                                                                                                      |
| -------------------- | ---------------------------------------------------------------------------------------------------------- |
| Product scope        | All active products (no `CatalogId__c` for this customer)                                                  |
| Pricebook resolution | `loadPricesByProduct()` loads **all** active `PricebookEntry` records for in-scope products — no filtering |
| Price payload        | `ec_price` emitted as a dictionary keyed by raw `Pricebook2Id` or `Pricebook2Id:SellingModelId`            |
| WebStoreId\_\_c      | Used only for Buyer Group entitlement resolution                                                           |
| Scheduling           | 1–4 native `CronTrigger` per config per sync mode                                                          |
| Chaining             | None — all batches launched independently                                                                  |

---

## Part A: Multi-Pricebook / Multi-Store Price Resolution

### A.1 — New CMDT Field: `PricebookIds__c`

**File:** `force-app/main/default/objects/CatalogJobConfig__mdt/fields/PricebookIds__c.field-meta.xml`

| Property      | Value                                                                                                                                  |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Type          | LongTextArea                                                                                                                           |
| Length        | 32768                                                                                                                                  |
| Visible Lines | 3                                                                                                                                      |
| Required      | No                                                                                                                                     |
| Description   | CSV of Pricebook2 IDs (18-char) to include in the export. When blank, all active pricebook entries are included (backward-compatible). |
| Manageability | SubscriberControlled                                                                                                                   |

**Behavior:**

- Blank/null → current behavior (all pricebooks exported)
- Populated → only `PricebookEntry` records whose `Pricebook2Id` is in the list are included

### A.2 — New CMDT Field: `WebStoreIds__c`

**File:** `force-app/main/default/objects/CatalogJobConfig__mdt/fields/WebStoreIds__c.field-meta.xml`

| Property      | Value                                                                                                                                                                                   |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Type          | LongTextArea                                                                                                                                                                            |
| Length        | 32768                                                                                                                                                                                   |
| Visible Lines | 3                                                                                                                                                                                       |
| Required      | No                                                                                                                                                                                      |
| Description   | CSV of WebStore IDs. Used to auto-resolve associated pricebooks via `WebStorePricebook` when `PricebookIds__c` is blank. Also used for multi-store buyer group availability resolution. |
| Manageability | SubscriberControlled                                                                                                                                                                    |

**Resolution priority:**

1. If `PricebookIds__c` is populated → use those pricebook IDs directly
2. Else if `WebStoreIds__c` is populated → query `WebStorePricebook` to resolve pricebook IDs
3. Else → no filter (all pricebooks, current behavior)

### A.3 — New Utility: `WebStorePricebookResolver.cls`

**File:** `force-app/main/default/classes/WebStorePricebookResolver.cls`

```apex
public with sharing class WebStorePricebookResolver {

  /**
   * Given a CSV of WebStore IDs, returns a Map of Pricebook2Id → WebStore Name.
   * Queries the WebStorePricebook junction object.
   */
  public static Map<Id, String> resolvePricebooksByWebStoreIds(String webStoreIdsCsv) { ... }

  /**
   * Given a CSV of Pricebook2 IDs, returns a Map of Pricebook2Id → Pricebook2 Name.
   */
  public static Map<Id, String> resolvePricebookNames(String pricebookIdsCsv) { ... }

  /**
   * Resolves the effective pricebook filter set from a CatalogJobConfig__mdt.
   * Returns null if no filter should be applied (backward-compatible).
   */
  public static Set<Id> resolveEffectivePricebookIds(CatalogJobConfig__mdt jobConfig) { ... }
}
```

**Dependencies:** Queries `WebStorePricebook` (standard B2B Commerce junction: WebStoreId, Pricebook2Id).

### A.4 — Modify `CatalogProductExportSupport.loadPricesByProduct()`

**File:** `force-app/main/default/classes/CatalogProductExportSupport.cls`

**Change:** Add an overloaded method or modify the existing one to accept an optional `Set<Id> targetPricebookIds`:

```apex
public static Map<Id, Map<String, Decimal>> loadPricesByProduct(
  List<Product2> scope,
  Id stdPricebookId,
  Set<Id> targetPricebookIds  // nullable — null means no filter
) {
  String query = 'SELECT Id, Product2Id, Pricebook2Id, UnitPrice, ProductSellingModelId '
    + 'FROM PricebookEntry '
    + 'WHERE Product2Id IN :scope AND IsActive = TRUE AND UnitPrice != NULL';

  if (targetPricebookIds != null && !targetPricebookIds.isEmpty()) {
    query += ' AND Pricebook2Id IN :targetPricebookIds';
  }

  // ... rest of existing logic unchanged
}
```

**Backward compatibility:** The existing two-parameter signature calls the new one with `null`.

### A.5 — Modify `ProductCatalogExportBatch` Constructor

**File:** `force-app/main/default/classes/ProductCatalogExportBatch.cls`

**Change:** Resolve the effective pricebook set once during construction and store it as an instance variable:

```apex
private Set<Id> targetPricebookIds;

// In constructor:
this.targetPricebookIds = WebStorePricebookResolver.resolveEffectivePricebookIds(jobConfig);
```

**Pass to execute:**

```apex
Map<Id, Map<String, Decimal>> pricesByProduct =
  CatalogProductExportSupport.loadPricesByProduct(scope, stdPricebookId, targetPricebookIds);
```

Same change applies to `DeltaProductCatalogExportBatch`.

### A.6 — Update Price Key Strategy in Payload

**Current:** Keys are raw Salesforce IDs (`01sABC123...`).  
**Final compatibility decision:** Both explicit `PricebookIds__c` scopes and `WebStoreIds__c`-resolved scopes retain raw `Pricebook2` IDs. Scope configuration changes which prices are selected, but it never changes the downstream key contract.

**Final format:**

```json
{
  "ec_price": {
    "01s_SHARED": 99.99,
    "01s_SHARED:0jP_MONTHLY": 8.99,
    "01s_REGIONAL": 109.99
  }
}
```

**Implementation:** Pass a `Map<Id, String> pricebookIdToLabel` into `loadPricesByProduct()` (or resolve it once and pass to the builder context). Both scoped paths map each resolved Pricebook ID to its own raw string value.

**Change locations:**

- `CatalogProductExportSupport.loadPricesByProduct()` — use the resolved raw ID label as the key
- Or introduce a post-processing step that remaps keys before handing to the builder

### A.7 — Update `CatalogSyncStateService.buildResolvedTargetKey()`

**File:** `force-app/main/default/classes/CatalogSyncStateService.cls`

**Change:** Include `PricebookIds__c` and `WebStoreIds__c` in the resolved target key hash:

```apex
List<String> resolvedTarget = new List<String>{
  // ... existing entries ...
  'pricebookIds',    canonicalizeCsv(jobConfig.PricebookIds__c),
  'webStoreIds',     canonicalizeCsv(jobConfig.WebStoreIds__c)
};
```

This ensures that changing the pricebook scope invalidates delta readiness (forces a new full baseline).

### A.8 — Update All Config Loaders

Every SOQL that loads `CatalogJobConfig__mdt` must include the new fields. Affected classes:

- `ProductCatalogExportBatch.loadJobConfig()`
- `DeltaProductCatalogExportBatch.loadJobConfig()`
- `BuyerGroupAvailabilityExportBatch.loadJobConfig()`
- `EmbeddedBuyerGroupAccessExportBatch.loadJobConfig()`
- `CatalogProductSyncScheduler.loadJobConfig()`
- `CatalogJobRunner` (multiple locations)
- `CatalogSyncStateService` (multiple locations)
- `CoveoCommerceSetupController`

### A.9 — Buyer Group Availability with Multiple WebStores

**Current:** `BuyerGroupAvailabilityExportBatch` uses `jobConfig.WebStoreId__c` (singular).  
**New:** When `WebStoreIds__c` is populated, iterate over all WebStore IDs to resolve buyer groups across stores.

**Change:** Modify `BuyerGroupAvailabilityExportBatch.start()` to union `WebStoreBuyerGroup` records from all listed WebStore IDs.

---

## Part B: Chained Scheduling

### B.1 — New Class: `CatalogSyncChainQueueable.cls`

**File:** `force-app/main/default/classes/CatalogSyncChainQueueable.cls`

A `Queueable` that processes a queue of config developer names sequentially:

```apex
public with sharing class CatalogSyncChainQueueable implements Queueable, Database.AllowsCallouts {

  private List<String> pendingConfigDeveloperNames;
  private String syncMode;
  private Boolean includeAvailability;

  public CatalogSyncChainQueueable(
    List<String> configDeveloperNames,
    String syncMode,
    Boolean includeAvailability
  ) {
    this.pendingConfigDeveloperNames = configDeveloperNames;
    this.syncMode = syncMode;
    this.includeAvailability = includeAvailability;
  }

  public void execute(QueueableContext context) {
    if (pendingConfigDeveloperNames.isEmpty()) {
      return;
    }

    String currentConfig = pendingConfigDeveloperNames.remove(0);

    // Launch the batch for the current config
    launchBatchForConfig(currentConfig);

    // Chain the next config if any remain
    if (!pendingConfigDeveloperNames.isEmpty()) {
      System.enqueueJob(
        new CatalogSyncChainQueueable(pendingConfigDeveloperNames, syncMode, includeAvailability)
      );
    }
  }

  private void launchBatchForConfig(String configDeveloperName) { ... }
}
```

**Note:** Queueable chaining has a depth limit (currently 5 in synchronous context, unlimited in async-to-async). Since each link only enqueues after the batch is launched (not after it completes), this avoids the depth limit. If the customer needs sequential completion (batch N finishes before batch N+1 starts), the chain trigger moves to the batch's `finish()` method instead.

### B.2 — New Class: `CatalogChainedSyncScheduler.cls`

**File:** `force-app/main/default/classes/CatalogChainedSyncScheduler.cls`

A `Schedulable` that replaces N individual scheduled jobs with one:

```apex
global with sharing class CatalogChainedSyncScheduler implements Schedulable {

  private List<String> configDeveloperNames;
  private String syncMode;
  private Boolean includeAvailability;

  public CatalogChainedSyncScheduler(
    List<String> configDeveloperNames,
    String syncMode,
    Boolean includeAvailability
  ) {
    this.configDeveloperNames = configDeveloperNames;
    this.syncMode = syncMode;
    this.includeAvailability = includeAvailability;
  }

  global void execute(SchedulableContext context) {
    if (configDeveloperNames == null || configDeveloperNames.isEmpty()) {
      return;
    }

    System.enqueueJob(
      new CatalogSyncChainQueueable(configDeveloperNames, syncMode, includeAvailability)
    );
  }

  public static String scheduleChainedSync(
    List<String> configDeveloperNames,
    String syncMode,
    Boolean includeAvailability,
    String cronExpression
  ) { ... }

  public static void clearChainedSchedule(String jobNamePrefix) { ... }
}
```

**Result:** One `CronTrigger` fires → one `Queueable` chains through all configs → each config launches its batch independently.

### B.3 — Update `CatalogJobRunner` with Chain Support

**File:** `force-app/main/default/classes/CatalogJobRunner.cls`

Add methods:

```apex
public static void runAllActiveChained() { ... }
public static void runAllActiveAvailabilityChained() { ... }
```

These collect active config developer names and hand them to `CatalogSyncChainQueueable`.

### B.4 — LWC Admin Console Updates

**File:** `force-app/main/default/lwc/catalogJobConsole/`

- Add a "Schedule Chain" action that groups selected configs under one scheduled slot
- Display chain membership in the job inventory table
- Show chain progress in the run center

---

## Part C: New Field Metadata Definitions

| New File                                                              | Purpose                                                                        |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `objects/CatalogJobConfig__mdt/fields/PricebookIds__c.field-meta.xml` | CSV of Pricebook2 IDs to include                                               |
| `objects/CatalogJobConfig__mdt/fields/WebStoreIds__c.field-meta.xml`  | CSV of WebStore IDs for pricebook auto-resolution and multi-store availability |

---

## Execution Phases

### Phase 1: Multi-Pricebook Foundation (3 days)

**Status: Complete.** Explicit scope is fail-closed; a configured scope that resolves no pricebooks exports no prices.

| #   | Task                                                                        | Files                                   |
| --- | --------------------------------------------------------------------------- | --------------------------------------- |
| 1.1 | Add `PricebookIds__c` and `WebStoreIds__c` field metadata                   | `objects/CatalogJobConfig__mdt/fields/` |
| 1.2 | Create `WebStorePricebookResolver.cls` + test                               | `classes/`                              |
| 1.3 | Add `resolveEffectivePricebookIds()` to resolve the pricebook filter        | `WebStorePricebookResolver.cls`         |
| 1.4 | Overload `loadPricesByProduct()` with pricebook filter                      | `CatalogProductExportSupport.cls`       |
| 1.5 | Wire pricebook resolution into `ProductCatalogExportBatch` constructor      | `ProductCatalogExportBatch.cls`         |
| 1.6 | Wire pricebook resolution into `DeltaProductCatalogExportBatch` constructor | `DeltaProductCatalogExportBatch.cls`    |
| 1.7 | Update all SOQL config loaders to include new fields                        | Multiple files                          |
| 1.8 | Update `buildResolvedTargetKey()` with pricebook/webstore dimensions        | `CatalogSyncStateService.cls`           |
| 1.9 | Tests: pricebook filtering, WebStore resolution, backward compat            | New test classes                        |

### Phase 2: Price Key Compatibility (1 day)

**Status: Complete with backward-compatible raw keys.** Explicit and store-resolved scopes both use raw `Pricebook2` IDs and retain raw `Pricebook2Id:ProductSellingModelId` composed keys.

| #   | Task                                                                     | Files                               |
| --- | ------------------------------------------------------------------------ | ----------------------------------- |
| 2.1 | Resolve `Map<Id, String>` raw Pricebook ID labels for either scoped path | `WebStorePricebookResolver.cls`     |
| 2.2 | Preserve raw IDs while filtering the price map                           | `CatalogProductExportSupport.cls`   |
| 2.3 | Update tests to verify the legacy raw key formats                        | `WebStorePricebookResolverTest.cls` |

### Phase 3: Chained Scheduling (2 days)

**Status: Complete.** Full/delta mode enforcement, inactive-config skipping, product/access combinations, and shared minute/hourly/weekly schedules are implemented and tested.

| #   | Task                                                 | Files                  |
| --- | ---------------------------------------------------- | ---------------------- |
| 3.1 | Create `CatalogSyncChainQueueable.cls` + test        | `classes/`             |
| 3.2 | Create `CatalogChainedSyncScheduler.cls` + test      | `classes/`             |
| 3.3 | Add `runAllActiveChained()` to `CatalogJobRunner`    | `CatalogJobRunner.cls` |
| 3.4 | Integration test: chain launches batches in sequence | Test class             |

### Phase 4: Multi-Store Availability (1 day)

**Status: Complete.** Buyer Groups are unioned across selected stores and payloads expose sorted `sf_webstore_ids`, retaining `sf_webstore_id` only when one store applies.

| #   | Task                                                                                  | Files                                   |
| --- | ------------------------------------------------------------------------------------- | --------------------------------------- |
| 4.1 | Update `BuyerGroupAvailabilityExportBatch.start()` to support `WebStoreIds__c`        | `BuyerGroupAvailabilityExportBatch.cls` |
| 4.2 | Backward compat: fall back to singular `WebStoreId__c` when `WebStoreIds__c` is blank | Same                                    |
| 4.3 | Test: multi-store buyer group union                                                   | Test class                              |

### Phase 5: LWC & Documentation (1–2 days)

**Status: Complete with persistent chain membership/progress display deferred.** Setup exposes both scope selectors and chain scheduling; the run center exposes resolved scope details.

| #   | Task                                                                                                            | Files                    |
| --- | --------------------------------------------------------------------------------------------------------------- | ------------------------ |
| 5.1 | Add multi-store pricebook configuration UI to setup workspace                                                   | `lwc/catalogJobConsole/` |
| 5.2 | Add chain scheduling UI                                                                                         | Same                     |
| 5.3 | Update README with new fields and configuration examples                                                        | `README.md`              |
| 5.4 | Add new Apex class access to the admin permission set (CMDT fields do not use ordinary field-level permissions) | `permissionsets/`        |

---

## Final Multi-Store Pricing Semantics

`WebStoreIds__c` controls Pricebook discovery and filtering; it does not become part of the price key. For each configured Web Store, the resolver loads its `WebStorePricebook` associations and computes a set union of the resulting `Pricebook2` IDs. Because this is a set, a Pricebook shared by multiple stores is exported once.

```txt
Store A -> Pricebook Shared, Pricebook US
Store B -> Pricebook Shared, Pricebook CA
Result  -> Pricebook Shared, Pricebook US, Pricebook CA
```

The final `ec_price` dictionary remains flat. Store-resolved keys preserve the legacy raw formats `<Pricebook2Id>` and `<Pricebook2Id>:<ProductSellingModelId>`. They do not use `<WebStoreId>:<Pricebook2Id>` aliases because `WebStorePricebook` membership does not change the underlying Pricebook Entry price. Adding store-qualified aliases would duplicate shared prices and break existing downstream key lookups.

If `PricebookIds__c` is also configured, its explicit Pricebook list takes precedence for pricing. `WebStoreIds__c` can still be used independently as the multi-store Buyer Group availability scope.

---

## Backward Compatibility Contract

| Scenario                                                     | Behavior                                                                                                                                     |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `PricebookIds__c` blank + `WebStoreIds__c` blank             | **No change.** All pricebook entries exported, keys remain raw IDs.                                                                          |
| `PricebookIds__c` populated                                  | Only explicitly listed Pricebooks are included. Keys remain raw `Pricebook2` IDs. This pricing scope takes precedence over `WebStoreIds__c`. |
| One `WebStoreIds__c` value, `PricebookIds__c` blank          | Auto-resolves that store's Pricebooks through `WebStorePricebook`; keys remain raw `Pricebook2` IDs.                                         |
| Multiple `WebStoreIds__c` values, `PricebookIds__c` blank    | Exports the deduplicated union of all linked Pricebooks. A shared Pricebook appears once; keys remain raw IDs.                               |
| Resolved Pricebook has a Product Selling Model               | Uses the flat raw `<Pricebook2Id>:<ProductSellingModelId>` key; the Web Store ID is not prefixed.                                            |
| Configured Pricebook or Web Store scope resolves to no books | Exports no prices and fails closed; it never falls back to an unscoped all-Pricebook export.                                                 |
| Existing scheduled jobs                                      | Continue working unchanged. Chained scheduling is opt-in.                                                                                    |
| `WebStoreId__c` (singular, existing)                         | Continues to work for Buyer Group availability. `WebStoreIds__c` takes precedence when populated.                                            |

---

## Risk & Mitigation

| Risk                                               | Impact                                               | Mitigation                                                                                                      |
| -------------------------------------------------- | ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `WebStorePricebook` object not present in all orgs | An explicit store scope cannot be resolved           | Guard with schema checks and fail with a clear configuration error; never fall back to an unscoped price export |
| Queueable chain depth limit                        | Chain stops mid-way                                  | Use async-to-async chaining (unlimited depth) rather than sync invocation                                       |
| Large price dictionaries bloat payload             | Heap/callout size limits                             | `PricebookIds__c` filtering keeps only relevant prices; batch size tuning via `BatchSize__c`                    |
| Delta readiness invalidation                       | First run after config change requires full baseline | Expected and documented; same behavior as changing any other config dimension                                   |

---

## Estimated Total Effort

| Phase                                | Days         |
| ------------------------------------ | ------------ |
| Phase 1 — Multi-Pricebook Foundation | 3            |
| Phase 2 — Price Key Labeling         | 1            |
| Phase 3 — Chained Scheduling         | 2            |
| Phase 4 — Multi-Store Availability   | 1            |
| Phase 5 — LWC & Documentation        | 1–2          |
| **Total**                            | **8–9 days** |

---

## Success Criteria

1. A single `CatalogJobConfig__mdt` with `WebStoreIds__c = "0ZE...A, 0ZE...B, 0ZE...C"` exports products with per-store prices in one payload
2. The customer's scheduled job count drops from ~40 to ~8 (or fewer)
3. Existing single-store configs with no new fields populated continue to work identically
4. Delta readiness correctly invalidates when pricebook scope changes
5. Buyer Group availability resolves entitlements across all listed WebStores
