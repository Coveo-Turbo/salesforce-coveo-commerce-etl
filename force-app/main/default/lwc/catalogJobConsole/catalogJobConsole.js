import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";

import getConsoleConfigs from "@salesforce/apex/CatalogJobRunner.getConsoleConfigs";
import runSingle from "@salesforce/apex/CatalogJobRunner.runSingle";
import runSingleAvailability from "@salesforce/apex/CatalogJobRunner.runSingleAvailability";
import runSingleBoth from "@salesforce/apex/CatalogJobRunner.runSingleBoth";
import runAllActive from "@salesforce/apex/CatalogJobRunner.runAllActive";
import runAllActiveAvailability from "@salesforce/apex/CatalogJobRunner.runAllActiveAvailability";
import runAllActiveBoth from "@salesforce/apex/CatalogJobRunner.runAllActiveBoth";
import getRunSnapshots from "@salesforce/apex/CatalogJobRunner.getRunSnapshots";
import abortCurrentProductRun from "@salesforce/apex/CatalogJobRunner.abortCurrentProductRun";
import abortRunJob from "@salesforce/apex/CatalogJobRunner.abortRunJob";

const POLL_INTERVAL_MS = 4000;
const CONFIG_REFRESH_INTERVAL_MS = 15000;
const RUN_STORAGE_KEY = "catalogJobConsoleRuns:v1";
const ACTIVITY_STORAGE_KEY = "catalogJobConsoleActivity:v1";
const MAX_RUNS = 8;
const MAX_ACTIVITY_ITEMS = 18;
const BUYER_GROUP_MODE_DISABLED = "Disabled";
const BUYER_GROUP_MODE_PAIRED = "PairedSource";
const BUYER_GROUP_MODE_EMBEDDED = "Embedded";
const BUYER_GROUP_MODE_DUAL = "DualWrite";
const SYNC_MODE_FULL = "Full";
const SYNC_MODE_DELTA = "Delta";
const SCHEDULE_CADENCE_MINUTES = "Minutes";
const SCHEDULE_CADENCE_HOURLY = "Hourly";
const SCHEDULE_CADENCE_WEEKLY = "Weekly";
const SCHEDULE_DAY_LABELS = {
  SUN: "Sunday",
  MON: "Monday",
  TUE: "Tuesday",
  WED: "Wednesday",
  THU: "Thursday",
  FRI: "Friday",
  SAT: "Saturday"
};

function resolveBuyerGroupAvailabilityMode(mode, legacyEnabled = false) {
  switch (mode) {
    case BUYER_GROUP_MODE_PAIRED:
    case BUYER_GROUP_MODE_EMBEDDED:
    case BUYER_GROUP_MODE_DUAL:
    case BUYER_GROUP_MODE_DISABLED:
      return mode;
    default:
      return legacyEnabled
        ? BUYER_GROUP_MODE_PAIRED
        : BUYER_GROUP_MODE_DISABLED;
  }
}

function isBuyerGroupAccessEnabled(mode) {
  return resolveBuyerGroupAvailabilityMode(mode) !== BUYER_GROUP_MODE_DISABLED;
}

function usesPairedSource(mode) {
  const resolvedMode = resolveBuyerGroupAvailabilityMode(mode);
  return (
    resolvedMode === BUYER_GROUP_MODE_PAIRED ||
    resolvedMode === BUYER_GROUP_MODE_DUAL
  );
}

function usesEmbeddedAccess(mode) {
  const resolvedMode = resolveBuyerGroupAvailabilityMode(mode);
  return (
    resolvedMode === BUYER_GROUP_MODE_EMBEDDED ||
    resolvedMode === BUYER_GROUP_MODE_DUAL
  );
}

function formatBuyerGroupAvailabilityMode(mode) {
  switch (resolveBuyerGroupAvailabilityMode(mode)) {
    case BUYER_GROUP_MODE_PAIRED:
      return "Paired Source";
    case BUYER_GROUP_MODE_EMBEDDED:
      return "Embedded";
    case BUYER_GROUP_MODE_DUAL:
      return "Dual Write";
    default:
      return "Disabled";
  }
}

export default class CatalogJobConsole extends LightningElement {
  configs;
  error;
  selectedConfigId;
  runSessions = [];
  activityFeed = [];
  pollTimerId;
  configRefreshTimerId;
  isPolling = false;
  isRefreshingConfigs = false;
  wiredConfigsResult;

  connectedCallback() {
    this.restoreRunState();
    this.startPollingIfNeeded();
    this.startConfigRefresh();
  }

  disconnectedCallback() {
    this.stopPolling();
    this.stopConfigRefresh();
  }

  @wire(getConsoleConfigs)
  wiredConfigs(result) {
    this.wiredConfigsResult = result;
    const { data, error } = result;
    if (data) {
      const nextSelectedId = data.some(
        (config) => config.DeveloperName === this.selectedConfigId
      )
        ? this.selectedConfigId
        : data[0]?.DeveloperName;
      this.configs = data.map((config) =>
        this.decorateConfig(config, nextSelectedId)
      );
      this.selectedConfigId = this.configs.length ? nextSelectedId : null;
      this.error = undefined;
    } else if (error) {
      this.error = error;
      this.configs = undefined;
    }
  }

  async handleRefreshStatus() {
    await this.refreshConfigs();
  }

  get hasConfigs() {
    return Array.isArray(this.configs) && this.configs.length > 0;
  }

  get selectedConfig() {
    if (!this.hasConfigs || !this.selectedConfigId) {
      return null;
    }
    return (
      this.configs.find((config) => config.id === this.selectedConfigId) || null
    );
  }

  get hasSelectedConfig() {
    return !!this.selectedConfig;
  }

  get selectedConfigStatusClass() {
    return (
      this.selectedConfig?.activeStatusClass || "cc-badge cc-badge--neutral"
    );
  }

  get selectedConfigAvailabilityClass() {
    return (
      this.selectedConfig?.availabilityStatusClass ||
      "cc-badge cc-badge--neutral"
    );
  }

  get selectedConfigProductSyncClass() {
    return (
      this.selectedConfig?.productSyncStatusClass ||
      "cc-badge cc-badge--neutral"
    );
  }

  get selectedConfigQuickStatusClass() {
    return (
      this.selectedConfig?.quickStatusClass || "cc-badge cc-badge--neutral"
    );
  }

  get totalJobs() {
    return this.configs ? this.configs.length : 0;
  }

  get activeJobs() {
    return this.configs
      ? this.configs.filter((config) => config.IsActive__c).length
      : 0;
  }

  get fullSyncJobs() {
    return this.configs
      ? this.configs.filter((config) => config.syncMode === SYNC_MODE_FULL)
          .length
      : 0;
  }

  get deltaSyncJobs() {
    return this.configs
      ? this.configs.filter((config) => config.syncMode === SYNC_MODE_DELTA)
          .length
      : 0;
  }

  get availabilityReadyJobs() {
    return this.configs
      ? this.configs.filter((config) => config.buyerGroupAccessEnabled).length
      : 0;
  }

  get inventoryTableRows() {
    if (!this.hasConfigs) {
      return [];
    }

    return [...this.configs].sort((left, right) => {
      if (left.syncMode !== right.syncMode) {
        return left.syncMode === SYNC_MODE_FULL ? -1 : 1;
      }

      if (left.IsActive__c !== right.IsActive__c) {
        return left.IsActive__c ? -1 : 1;
      }

      return (left.label || "").localeCompare(right.label || "");
    });
  }

  get liveRunsCount() {
    return this.runSessions.filter((session) => !session.isTerminal).length;
  }

  get hasRunSessions() {
    return this.runSessions.length > 0;
  }

  get visibleRunSessions() {
    return this.runSessions.slice(0, MAX_RUNS);
  }

  get hasActivityFeed() {
    return this.activityFeed.length > 0;
  }

  get visibleActivityFeed() {
    return this.activityFeed.slice(0, MAX_ACTIVITY_ITEMS);
  }

  get hasIncompleteRuns() {
    return this.getIncompleteJobIds().length > 0;
  }

  get isLoading() {
    return !this.configs && !this.error;
  }

  get errorMessage() {
    if (!this.error) {
      return "";
    }
    if (Array.isArray(this.error.body)) {
      return this.error.body.map((item) => item.message).join(", ");
    }
    if (this.error.body?.message) {
      return this.error.body.message;
    }
    return "Unknown error";
  }

  get selectedConfigFactRows() {
    if (!this.selectedConfig) {
      return [];
    }

    return [
      {
        label: "Sync Mode",
        value: this.selectedConfig.syncModeLabel
      },
      {
        label: "Delta Status",
        value: this.selectedConfig.deltaStatusDetail
      },
      {
        label: "Baseline Full",
        value: this.selectedConfig.baselineFullConfigLabel
      },
      {
        label: "Catalog",
        value: this.selectedConfig.catalogLabel
      },
      {
        label: "Locale",
        value: this.selectedConfig.localeLabel
      },
      {
        label: "Builder",
        value: this.selectedConfig.builderSummary
      },
      {
        label: "Product Source",
        value: this.selectedConfig.productSourceLabel
      },
      {
        label: "Access Mode",
        value: this.selectedConfig.buyerGroupAvailabilityModeLabel
      },
      {
        label: "Availability Source",
        value: this.selectedConfig.availabilitySourceLabel
      },
      {
        label: "Web Store",
        value: this.selectedConfig.webStoreLabel
      },
      {
        label: "Filter",
        value: this.selectedConfig.scopeSummary
      },
      {
        label: "Extra Fields",
        value: this.selectedConfig.extraFieldsSummary
      },
      {
        label: "Last Full Sync",
        value: this.selectedConfig.lastSuccessfulFullSyncLabel
      },
      {
        label: "Last Successful Sync",
        value: this.selectedConfig.lastSuccessfulSyncLabel
      },
      {
        label: "Current Product Job",
        value: this.selectedConfig.quickStatusSummary
      },
      {
        label: "Schedule",
        value: this.selectedConfig.scheduleSummary
      }
    ];
  }

  get runMonitorSubtitle() {
    if (!this.hasRunSessions) {
      return "Launch a sync to start tracking live batch progress here.";
    }

    if (this.hasIncompleteRuns) {
      return "Auto-refreshing every 4 seconds while active runs are in progress.";
    }

    return "Recent run history from this console session.";
  }

  get selectedRunHeading() {
    if (!this.selectedConfig) {
      return "Select a catalog job";
    }
    return this.selectedConfig.label;
  }

  get selectedRunSubtitle() {
    if (!this.selectedConfig) {
      return "Choose a configuration to launch products or Buyer Group access syncs.";
    }
    return `${this.selectedConfig.syncModeLabel} • ${this.selectedConfig.catalogLabel} • ${this.selectedConfig.localeLabel} • ${this.selectedConfig.builderLabel}`;
  }

  get availabilityDisabledMessage() {
    if (this.selectedConfig?.buyerGroupAccessEnabled) {
      return "";
    }
    return "Buyer Group access is disabled for this configuration.";
  }

  get productDisabledMessage() {
    if (!this.selectedConfig?.productDisabled) {
      return "";
    }

    return (
      this.selectedConfig.deltaReadinessMessage ||
      "This product sync is not ready to launch."
    );
  }

  get launchpadNote() {
    return this.productDisabledMessage || this.availabilityDisabledMessage;
  }

  get selectedProductStatusSummary() {
    return this.selectedConfig?.quickStatusSummary || "No active product run";
  }

  get selectedProductStatusMeta() {
    return this.selectedConfig?.quickStatusMeta || "Manual launch only";
  }

  get canAbortSelectedProductRun() {
    return this.selectedConfig?.canAbortCurrentProductRun === true;
  }

  get abortSelectedProductRunDisabled() {
    return !this.canAbortSelectedProductRun;
  }

  get selectedProductRunLabel() {
    return this.selectedConfig?.productRunLabel || "Run Products";
  }

  get showRunSelectedBoth() {
    if (!this.selectedConfig) {
      return false;
    }

    return !(
      this.selectedConfig.usesEmbeddedAccess &&
      !this.selectedConfig.usesPairedSource
    );
  }

  handleSelectConfig(event) {
    const configId = event.currentTarget?.dataset?.configId;
    if (!configId || configId === this.selectedConfigId) {
      return;
    }

    this.selectedConfigId = configId;
    this.configs = this.configs.map((config) =>
      this.decorateConfig(config, this.selectedConfigId)
    );
  }

  async handleRunSelectedProducts() {
    if (!this.selectedConfig) {
      return;
    }

    await this.launchRuns(
      () =>
        runSingle({
          jobConfigDeveloperName: this.selectedConfig.developerName
        }),
      `${this.selectedConfig.label}: started ${this.selectedConfig.syncModeLabel.toLowerCase()} product sync`
    );
  }

  async handleRunSelectedAvailability() {
    if (!this.selectedConfig) {
      return;
    }

    await this.launchRuns(
      () =>
        runSingleAvailability({
          jobConfigDeveloperName: this.selectedConfig.developerName
        }),
      `${this.selectedConfig.label}: started access sync`
    );
  }

  async handleRunSelectedBoth() {
    if (!this.selectedConfig) {
      return;
    }

    await this.launchRuns(
      () =>
        runSingleBoth({
          jobConfigDeveloperName: this.selectedConfig.developerName
        }),
      `${this.selectedConfig.label}: started ${this.selectedConfig.syncModeLabel.toLowerCase()} product and access syncs`
    );
  }

  async handleRunAllProducts() {
    await this.launchRuns(
      () => runAllActive(),
      "Started product syncs for all active configurations"
    );
  }

  async handleAbortSelectedProductRun() {
    if (!this.selectedConfig || !this.canAbortSelectedProductRun) {
      return;
    }

    try {
      const jobId = await abortCurrentProductRun({
        jobConfigDeveloperName: this.selectedConfig.developerName
      });
      this.addActivity(
        `${this.selectedConfig.label}: abort requested for product job ${jobId}`
      );
      this.showToast(
        "Abort requested",
        `${this.selectedConfig.label}: stopping the active product sync`,
        "success"
      );
      await this.pollRunSnapshots();
      await this.refreshConfigs();
    } catch (error) {
      this.showToast("Error", this.reduceError(error), "error");
      // eslint-disable-next-line no-console
      console.error("Abort current product run error", error);
    }
  }

  async handleAbortStage(event) {
    const jobId = event.currentTarget?.dataset?.jobId;
    const jobLabel = event.currentTarget?.dataset?.jobLabel || "job";
    if (!jobId) {
      return;
    }

    try {
      await abortRunJob({ jobId });
      this.addActivity(`Abort requested for ${jobLabel}`);
      this.showToast("Abort requested", `Stopping ${jobLabel}`, "success");
      await this.pollRunSnapshots();
      await this.refreshConfigs();
    } catch (error) {
      this.showToast("Error", this.reduceError(error), "error");
      // eslint-disable-next-line no-console
      console.error("Abort run stage error", error);
    }
  }

  async handleRunAllAvailability() {
    await this.launchRuns(
      () => runAllActiveAvailability(),
      "Started access syncs for active Buyer Group-enabled configurations"
    );
  }

  async handleRunAllBoth() {
    await this.launchRuns(
      () => runAllActiveBoth(),
      "Started syncs for all active configurations"
    );
  }

  async launchRuns(requestFn, successMessage) {
    try {
      const response = await requestFn();
      const launches = this.normalizeLaunches(response);

      if (!launches.length) {
        this.showToast(
          "No jobs started",
          "There were no eligible catalog jobs to launch.",
          "info"
        );
        return;
      }

      this.recordLaunches(launches);
      this.showToast("Sync started", successMessage, "success");
      await this.pollRunSnapshots();
      await this.refreshConfigs();
      this.startPollingIfNeeded();
    } catch (error) {
      const message = this.reduceError(error);
      this.showToast("Error", message, "error");
      // eslint-disable-next-line no-console
      console.error("Catalog job launch error", error);
    }
  }

  normalizeLaunches(response) {
    if (!response) {
      return [];
    }
    return Array.isArray(response) ? response : [response];
  }

  recordLaunches(launches) {
    const nextRuns = launches.map((launch) => this.createRunSession(launch));
    nextRuns.forEach((launch) => {
      this.addActivity(
        `${launch.label}: ${this.describeLaunchMode(
          launch.mode,
          launch.jobs
        )} started`
      );
    });

    this.runSessions = [...nextRuns, ...this.runSessions]
      .slice(0, MAX_RUNS)
      .map((session) => this.decorateRunSession(session));

    this.persistRunState();
  }

  createRunSession(launch) {
    return {
      runKey: launch.runKey,
      developerName: launch.developerName,
      label: launch.label,
      mode: launch.mode,
      availabilityEnabled: launch.availabilityEnabled,
      buyerGroupAvailabilityMode: launch.buyerGroupAvailabilityMode,
      launchedAt: launch.launchedAt,
      jobs: (launch.jobs || []).map((job) => ({
        jobId: job.jobId,
        channel: job.channel,
        label: job.label,
        impactedProductCount: job.impactedProductCount,
        changedRootProductCount: job.changedRootProductCount,
        exportProductCount: job.exportProductCount,
        scopeSummary: job.scopeSummary || "",
        status: "Queued",
        jobItemsProcessed: 0,
        totalJobItems: 0,
        numberOfErrors: 0,
        extendedStatus: "",
        isTerminal: false,
        createdDate: launch.launchedAt,
        completedDate: null
      }))
    };
  }

  async pollRunSnapshots() {
    const pendingJobIds = this.getIncompleteJobIds();
    if (!pendingJobIds.length || this.isPolling) {
      return;
    }

    this.isPolling = true;

    try {
      const snapshots = await getRunSnapshots({ jobIds: pendingJobIds });
      if (snapshots?.length) {
        this.mergeSnapshots(snapshots);
        await this.refreshConfigs();
      }
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("getRunSnapshots error", error);
    } finally {
      this.isPolling = false;
      if (!this.getIncompleteJobIds().length) {
        this.stopPolling();
      }
    }
  }

  mergeSnapshots(snapshots) {
    const snapshotByJobId = new Map(
      snapshots.map((snapshot) => [snapshot.jobId, snapshot])
    );

    const nextRuns = this.runSessions.map((runSession) => {
      const nextJobs = runSession.jobs.map((job) => {
        const snapshot = snapshotByJobId.get(job.jobId);
        if (!snapshot) {
          return job;
        }

        if (job.status !== snapshot.status) {
          this.addActivity(
            `${runSession.label}: ${this.describeStageChange(job.channel, snapshot.status)}`
          );
        }

        return {
          ...job,
          ...snapshot,
          impactedProductCount:
            snapshot.impactedProductCount ?? job.impactedProductCount,
          changedRootProductCount:
            snapshot.changedRootProductCount ?? job.changedRootProductCount,
          exportProductCount:
            snapshot.exportProductCount ?? job.exportProductCount,
          scopeSummary: snapshot.scopeSummary ?? job.scopeSummary
        };
      });

      return this.decorateRunSession({
        ...runSession,
        jobs: nextJobs
      });
    });

    this.runSessions = nextRuns;
    this.persistRunState();
  }

  startPollingIfNeeded() {
    if (!this.getIncompleteJobIds().length || this.pollTimerId) {
      return;
    }

    this.pollTimerId = window.setInterval(() => {
      this.pollRunSnapshots();
    }, POLL_INTERVAL_MS);
  }

  startConfigRefresh() {
    if (this.configRefreshTimerId) {
      return;
    }

    this.configRefreshTimerId = window.setInterval(() => {
      this.refreshConfigs();
    }, CONFIG_REFRESH_INTERVAL_MS);
  }

  stopConfigRefresh() {
    if (!this.configRefreshTimerId) {
      return;
    }

    window.clearInterval(this.configRefreshTimerId);
    this.configRefreshTimerId = null;
  }

  async refreshConfigs() {
    if (
      !this.wiredConfigsResult ||
      this.isRefreshingConfigs ||
      document.visibilityState === "hidden"
    ) {
      return;
    }

    this.isRefreshingConfigs = true;
    try {
      await refreshApex(this.wiredConfigsResult);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Catalog job config refresh error", error);
    } finally {
      this.isRefreshingConfigs = false;
    }
  }

  stopPolling() {
    if (this.pollTimerId) {
      window.clearInterval(this.pollTimerId);
      this.pollTimerId = null;
    }
  }

  getIncompleteJobIds() {
    return this.runSessions.reduce((jobIds, runSession) => {
      runSession.jobs.forEach((job) => {
        if (!job.isTerminal && job.jobId) {
          jobIds.push(job.jobId);
        }
      });
      return jobIds;
    }, []);
  }

  addActivity(message) {
    const entry = {
      key: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      message,
      timestamp: new Date().toISOString(),
      timestampLabel: this.formatTimestamp(new Date().toISOString())
    };

    this.activityFeed = [entry, ...this.activityFeed].slice(
      0,
      MAX_ACTIVITY_ITEMS
    );
  }

  persistRunState() {
    try {
      window.sessionStorage.setItem(
        RUN_STORAGE_KEY,
        JSON.stringify(this.runSessions)
      );
      window.sessionStorage.setItem(
        ACTIVITY_STORAGE_KEY,
        JSON.stringify(this.activityFeed)
      );
    } catch (error) {
      // eslint-disable-next-line no-console
      console.warn("Unable to persist run-center state", error);
    }
  }

  restoreRunState() {
    try {
      const storedRuns = window.sessionStorage.getItem(RUN_STORAGE_KEY);
      const storedActivity =
        window.sessionStorage.getItem(ACTIVITY_STORAGE_KEY);

      if (storedRuns) {
        const parsedRuns = JSON.parse(storedRuns);
        this.runSessions = Array.isArray(parsedRuns)
          ? parsedRuns.map((session) => this.decorateRunSession(session))
          : [];
      }

      if (storedActivity) {
        const parsedActivity = JSON.parse(storedActivity);
        this.activityFeed = Array.isArray(parsedActivity) ? parsedActivity : [];
      }
    } catch (error) {
      this.runSessions = [];
      this.activityFeed = [];
    }
  }

  decorateConfig(config, selectedConfigId) {
    const filterText = this.normalizeText(
      config.ProductFilter__c,
      "No product filter"
    );
    const extraFields = this.splitCsv(config.AdditionalProductFields__c);
    const isSelected = config.DeveloperName === selectedConfigId;
    const syncMode =
      config.SyncMode__c === SYNC_MODE_DELTA ? SYNC_MODE_DELTA : SYNC_MODE_FULL;
    const buyerGroupAvailabilityMode = resolveBuyerGroupAvailabilityMode(
      config.BuyerGroupAvailabilityMode__c,
      config.EnableBuyerGroupAvailability__c
    );
    const buyerGroupAccessEnabled = isBuyerGroupAccessEnabled(
      buyerGroupAvailabilityMode
    );
    const usesPaired = usesPairedSource(buyerGroupAvailabilityMode);
    const usesEmbedded = usesEmbeddedAccess(buyerGroupAvailabilityMode);
    const buyerGroupAvailabilityModeLabel = formatBuyerGroupAvailabilityMode(
      buyerGroupAvailabilityMode
    );
    const accessDestinationLabel = this.describeAccessDestination(
      config.SourceId__c,
      config.AvailabilitySourceId__c,
      buyerGroupAvailabilityMode
    );
    const deltaReady =
      syncMode === SYNC_MODE_DELTA ? config.deltaReady === true : true;
    const deltaReadinessMessage =
      config.deltaReadinessMessage ||
      (syncMode === SYNC_MODE_DELTA
        ? "Run the baseline full sync once before delta sync."
        : "Full sync establishes the baseline.");
    const deltaStatusDetail =
      syncMode === SYNC_MODE_DELTA
        ? deltaReady
          ? "Ready to launch"
          : deltaReadinessMessage
        : "This run seeds the trusted baseline";
    const productDisabled = syncMode === SYNC_MODE_DELTA && !deltaReady;
    const scheduleSummary = this.describeScheduleCadence(config);
    const quickStatus = this.describeQuickStatus(config, {
      syncMode,
      scheduleSummary
    });

    return {
      ...config,
      id: config.DeveloperName,
      developerName: config.DeveloperName,
      label: config.Label,
      syncMode,
      syncModeLabel:
        syncMode === SYNC_MODE_DELTA
          ? "Delta Product Sync"
          : "Full Product Sync",
      baselineFullConfigLabel: this.normalizeText(
        config.BaselineFullConfigDeveloperName__c,
        syncMode === SYNC_MODE_DELTA ? "Not configured" : "Self"
      ),
      lastSuccessfulFullSyncLabel: this.formatOptionalTimestamp(
        config.lastSuccessfulFullSyncAt,
        "Never"
      ),
      lastSuccessfulSyncLabel: this.formatOptionalTimestamp(
        config.lastSuccessfulSyncAt,
        "Never"
      ),
      deltaReady,
      deltaReadinessMessage,
      deltaStatusDetail,
      productRunLabel:
        syncMode === SYNC_MODE_DELTA
          ? "Run Delta Products"
          : "Run Full Products",
      productDisabled,
      bothDisabled: productDisabled || buyerGroupAccessEnabled !== true,
      buyerGroupAvailabilityMode,
      buyerGroupAvailabilityModeLabel,
      buyerGroupAccessEnabled,
      usesPairedSource: usesPaired,
      usesEmbeddedAccess: usesEmbedded,
      inventoryRowClass: isSelected
        ? "cc-config-table__row cc-config-table__row--selected"
        : "cc-config-table__row",
      cardClass: this.getConfigCardClass(isSelected),
      catalogLabel: this.normalizeText(config.CatalogId__c, "Catalog not set"),
      localeLabel: this.normalizeText(config.Locale__c, "Default locale"),
      builderLabel: this.normalizeText(config.BuilderType__c, "Default"),
      builderSummary: this.describeBuilder(config.BuilderType__c),
      productSourceLabel: this.normalizeText(
        config.SourceId__c,
        "No product source"
      ),
      availabilitySourceLabel: usesPaired
        ? this.normalizeText(
            config.AvailabilitySourceId__c,
            "Availability source missing"
          )
        : "Not required",
      accessDestinationLabel,
      webStoreLabel: buyerGroupAccessEnabled
        ? this.normalizeText(config.WebStoreId__c, "Web store missing")
        : "Not required",
      scopeSummary: filterText,
      extraFieldsSummary: extraFields.length
        ? `${extraFields.length} extra field${extraFields.length === 1 ? "" : "s"}`
        : "No extra fields",
      extraFieldsTitle: extraFields.length
        ? extraFields.join(", ")
        : "No extra fields",
      productSyncStatusLabel:
        syncMode === SYNC_MODE_DELTA
          ? deltaReady
            ? "Delta Ready"
            : "Delta Blocked"
          : "Full Baseline",
      productSyncStatusClass:
        syncMode === SYNC_MODE_DELTA
          ? deltaReady
            ? "cc-badge cc-badge--brand"
            : "cc-badge cc-badge--danger"
          : "cc-badge cc-badge--info",
      activeStatusLabel: config.IsActive__c ? "Active" : "Inactive",
      activeStatusClass: config.IsActive__c
        ? "cc-badge cc-badge--success"
        : "cc-badge cc-badge--neutral",
      availabilityStatusLabel: buyerGroupAccessEnabled
        ? buyerGroupAvailabilityModeLabel
        : "Access Disabled",
      availabilityStatusClass: buyerGroupAccessEnabled
        ? "cc-badge cc-badge--info"
        : "cc-badge cc-badge--neutral",
      availabilityDisabled: buyerGroupAccessEnabled !== true,
      inventorySyncSummary: `${syncMode === SYNC_MODE_DELTA ? "Delta" : "Full"} Product Sync`,
      inventorySyncMeta:
        syncMode === SYNC_MODE_DELTA
          ? deltaStatusDetail
          : `Baseline: ${this.normalizeText(
              config.BaselineFullConfigDeveloperName__c,
              "Self"
            )}`,
      quickStatusSummary: quickStatus.summary,
      quickStatusMeta: quickStatus.meta,
      quickStatusClass: quickStatus.className,
      quickStatusLabel: quickStatus.label,
      canAbortCurrentProductRun: quickStatus.canAbort,
      currentProductJobId: config.currentProductJobId || "",
      currentProductConfigDeveloperName:
        config.currentProductConfigDeveloperName || "",
      scheduleSummary,
      inventoryExperienceSummary: `${this.normalizeText(
        config.CatalogId__c,
        "Catalog not set"
      )} • ${this.normalizeText(config.Locale__c, "Default locale")}`,
      inventoryExperienceMeta: this.describeBuilder(config.BuilderType__c),
      inventorySourceSummary: this.normalizeText(
        config.SourceId__c,
        "No product source"
      ),
      inventorySourceMeta: filterText,
      inventoryAccessSummary: buyerGroupAvailabilityModeLabel,
      inventoryAccessMeta: accessDestinationLabel,
      inventoryStatusSummary: quickStatus.summary,
      inventoryStatusMeta: quickStatus.meta,
      inventoryLastSyncSummary: this.formatOptionalTimestamp(
        config.lastSuccessfulSyncAt,
        "Never"
      ),
      inventoryLastSyncMeta: `Full baseline: ${this.formatOptionalTimestamp(
        config.lastSuccessfulFullSyncAt,
        "Never"
      )}`
    };
  }

  decorateRunSession(runSession) {
    const stages = runSession.jobs.map((job) => this.decorateRunStage(job));
    const hasFailure = stages.some(
      (stage) => stage.status === "Failed" || stage.status === "Aborted"
    );
    const isComplete =
      stages.length > 0 && stages.every((stage) => stage.isTerminal);
    const isInProgress = stages.some((stage) => stage.status === "Processing");
    const hasActiveStages = stages.some((stage) => !stage.isTerminal);
    const progressPercent = Math.round(
      stages.reduce((sum, stage) => sum + stage.progressPercent, 0) /
        Math.max(stages.length, 1)
    );
    const startedAt = this.getRunStartTime(runSession, stages);
    const completedAt = this.getRunCompletedTime(stages);

    let overallStatusLabel = "Queued";
    let overallStatusClass = "cc-badge cc-badge--neutral";

    if (hasFailure) {
      overallStatusLabel = "Attention Required";
      overallStatusClass = "cc-badge cc-badge--danger";
    } else if (isComplete) {
      overallStatusLabel = "Complete";
      overallStatusClass = "cc-badge cc-badge--success";
    } else if (isInProgress) {
      overallStatusLabel = "In Progress";
      overallStatusClass = "cc-badge cc-badge--brand";
    }

    return {
      ...runSession,
      stages,
      progressPercent,
      isTerminal: isComplete || hasFailure,
      overallStatusLabel,
      overallStatusClass,
      launchedAtLabel: this.formatTimestamp(runSession.launchedAt),
      timingLabel: this.describeRunDuration({
        startedAt,
        completedAt,
        hasActiveStages,
        hasFailure,
        isComplete
      }),
      cardClass: hasFailure
        ? "cc-run-card cc-run-card--error"
        : isComplete
          ? "cc-run-card cc-run-card--complete"
          : "cc-run-card"
    };
  }

  decorateRunStage(job) {
    const status = job.status || "Queued";
    const progressPercent = this.getJobProgressPercent(job);
    const scopeSummary = this.describeJobScope(job);
    const batchesLabel = this.describeJobBatches(job, status);

    return {
      ...job,
      status,
      progressPercent,
      statusLabel: this.describeStageChange(job.channel, status),
      statusClass: this.getStageStatusClass(status),
      batchesLabel,
      extendedStatus: scopeSummary || job.extendedStatus || "",
      timingLabel: this.describeStageDuration(job),
      canAbort: !!job.jobId && status !== "Completed" && status !== "Failed" && status !== "Aborted"
    };
  }

  getRunStartTime(runSession, stages) {
    const timestamps = [
      runSession.launchedAt,
      ...stages.map((stage) => stage.createdDate)
    ]
      .map((value) => this.toTimestamp(value))
      .filter((value) => value !== null);

    if (!timestamps.length) {
      return null;
    }

    return Math.min(...timestamps);
  }

  getRunCompletedTime(stages) {
    const timestamps = stages
      .map((stage) => this.toTimestamp(stage.completedDate))
      .filter((value) => value !== null);

    if (!timestamps.length) {
      return null;
    }

    return Math.max(...timestamps);
  }

  describeRunDuration({
    startedAt,
    completedAt,
    hasActiveStages,
    hasFailure,
    isComplete
  }) {
    if (startedAt === null) {
      return "Waiting for timing data";
    }

    const effectiveEnd = completedAt ?? Date.now();
    const durationText = this.formatDuration(effectiveEnd - startedAt);

    if (hasActiveStages) {
      return `Elapsed ${durationText}`;
    }

    if (hasFailure) {
      return `Stopped after ${durationText}`;
    }

    if (isComplete) {
      return `Completed in ${durationText}`;
    }

    return `Queued for ${durationText}`;
  }

  describeStageDuration(job) {
    const startedAt = this.toTimestamp(job.createdDate);
    if (startedAt === null) {
      return "";
    }

    const completedAt = this.toTimestamp(job.completedDate);
    const effectiveEnd = completedAt ?? Date.now();
    const durationText = this.formatDuration(effectiveEnd - startedAt);

    if (job.status === "Completed") {
      return `Completed in ${durationText}`;
    }

    if (job.status === "Failed" || job.status === "Aborted") {
      return `Stopped after ${durationText}`;
    }

    if (job.status === "Processing") {
      return `Elapsed ${durationText}`;
    }

    return `Queued for ${durationText}`;
  }

  getJobProgressPercent(job) {
    if (job.status === "Completed") {
      return 100;
    }

    if (job.status === "Failed" || job.status === "Aborted") {
      return Math.max(
        5,
        this.safePercent(job.jobItemsProcessed, job.totalJobItems)
      );
    }

    if (job.totalJobItems > 0) {
      return this.safePercent(job.jobItemsProcessed, job.totalJobItems);
    }

    if (job.status === "Processing") {
      return 35;
    }

    return 0;
  }

  describeJobBatches(job, status) {
    if (job.totalJobItems > 0) {
      return `${job.jobItemsProcessed || 0} / ${job.totalJobItems} batches`;
    }

    if (job.exportProductCount === 0 && status === "Completed") {
      return "No changed products to export";
    }

    if (job.exportProductCount > 0) {
      return `${job.exportProductCount} product${
        job.exportProductCount === 1 ? "" : "s"
      } in export scope`;
    }

    if (status === "Processing") {
      return "Preparing batch metrics";
    }

    return "Waiting for batch metrics";
  }

  describeJobScope(job) {
    if (job.scopeSummary) {
      return job.scopeSummary;
    }

    if (
      job.impactedProductCount === undefined &&
      job.changedRootProductCount === undefined &&
      job.exportProductCount === undefined
    ) {
      return "";
    }

    if (job.exportProductCount === 0 && job.impactedProductCount > 0) {
      return `${job.impactedProductCount} impacted product${
        job.impactedProductCount === 1 ? "" : "s"
      } since last sync, but none matched this export scope`;
    }

    if (job.exportProductCount === 0) {
      return "No changed products since last sync";
    }

    return `${job.impactedProductCount || 0} impacted product${
      job.impactedProductCount === 1 ? "" : "s"
    } • ${job.changedRootProductCount || 0} changed root${
      job.changedRootProductCount === 1 ? "" : "s"
    } • ${job.exportProductCount} product${
      job.exportProductCount === 1 ? "" : "s"
    } queued for export`;
  }

  safePercent(processed, total) {
    if (!total) {
      return 0;
    }
    return Math.max(
      0,
      Math.min(100, Math.round(((processed || 0) / total) * 100))
    );
  }

  getStageStatusClass(status) {
    switch (status) {
      case "Completed":
        return "cc-stage-badge cc-stage-badge--success";
      case "Processing":
        return "cc-stage-badge cc-stage-badge--brand";
      case "Failed":
      case "Aborted":
        return "cc-stage-badge cc-stage-badge--danger";
      default:
        return "cc-stage-badge cc-stage-badge--neutral";
    }
  }

  describeLaunchMode(mode, jobs = []) {
    const channels = new Set((jobs || []).map((job) => job.channel));

    if (mode === "both" || (channels.has("products") && channels.size > 1)) {
      return "product and access syncs";
    }

    if (channels.has("access")) {
      return "embedded access sync";
    }

    switch (mode) {
      case "availability":
        return channels.has("availability")
          ? "availability sync"
          : "access sync";
      case "access":
        return "access sync";
      case "both":
        return "product and access syncs";
      default:
        return "product sync";
    }
  }

  describeStageChange(channel, status) {
    let subject = "Syncing products";
    if (channel === "availability") {
      subject = "Syncing availability";
    } else if (channel === "access") {
      subject = "Syncing embedded access";
    }

    switch (status) {
      case "Completed":
        return `${subject} complete`;
      case "Processing":
        return subject;
      case "Failed":
        return `${subject} failed`;
      case "Aborted":
        return `${subject} aborted`;
      default:
        return `${subject} queued`;
    }
  }

  describeQuickStatus(config, { syncMode, scheduleSummary }) {
    const currentStatus = config.currentProductJobStatus;
    const currentJobId = config.currentProductJobId;
    const currentRunLabel =
      config.currentProductRunMode === SYNC_MODE_DELTA ? "Delta" : "Full";
    const currentConfigDeveloperName =
      config.currentProductConfigDeveloperName || config.DeveloperName;

    if (config.currentProductIsActive === true && currentStatus) {
      const statusLabel = this.describeAsyncJobStatus(currentStatus);
      const startedAtLabel = this.formatOptionalTimestamp(
        config.currentProductStartedAt,
        "Just now"
      );
      const currentConfigMatches =
        currentConfigDeveloperName === config.DeveloperName;

      return {
        summary: `${currentRunLabel} sync ${statusLabel.toLowerCase()}`,
        meta: currentConfigMatches
          ? `Started ${startedAtLabel} • Job ${currentJobId}`
          : `Running via ${currentConfigDeveloperName} • Job ${currentJobId}`,
        label: statusLabel,
        className: this.getQuickStatusClass(currentStatus),
        canAbort: Boolean(currentJobId)
      };
    }

    if (config.isScheduled === true) {
      const scheduleStateLabel = this.describeScheduleState(config.scheduleState);
      return {
        summary: scheduleStateLabel,
        meta: scheduleSummary,
        label: scheduleStateLabel,
        className: this.getScheduleStateClass(config.scheduleState),
        canAbort: false
      };
    }

    return {
      summary: "Manual launch only",
      meta:
        syncMode === SYNC_MODE_DELTA
          ? config.deltaReady === true
            ? "Ready to launch from this console"
            : config.deltaReadinessMessage || "Waiting for baseline"
          : "Launch from this console when needed",
      label: "Manual",
      className: "cc-badge cc-badge--neutral",
      canAbort: false
    };
  }

  describeAsyncJobStatus(status) {
    switch (status) {
      case "Holding":
      case "Queued":
      case "Preparing":
        return "Queued";
      case "Processing":
        return "Running";
      case "Completed":
        return "Complete";
      case "Aborted":
        return "Aborted";
      case "Failed":
        return "Failed";
      default:
        return this.normalizeText(status, "Queued");
    }
  }

  describeScheduleState(state) {
    switch (state) {
      case "WAITING":
        return "Waiting";
      case "ACQUIRED":
      case "EXECUTING":
        return "Starting";
      case "PAUSED":
      case "PAUSED_BLOCKED":
        return "Paused";
      case "BLOCKED":
        return "Blocked";
      default:
        return "Scheduled";
    }
  }

  getQuickStatusClass(status) {
    switch (status) {
      case "Processing":
        return "cc-badge cc-badge--brand";
      case "Holding":
      case "Queued":
      case "Preparing":
        return "cc-badge cc-badge--neutral";
      case "Failed":
      case "Aborted":
        return "cc-badge cc-badge--danger";
      default:
        return "cc-badge cc-badge--success";
    }
  }

  getScheduleStateClass(state) {
    switch (state) {
      case "WAITING":
        return "cc-badge cc-badge--info";
      case "ACQUIRED":
      case "EXECUTING":
        return "cc-badge cc-badge--brand";
      case "BLOCKED":
      case "PAUSED":
      case "PAUSED_BLOCKED":
        return "cc-badge cc-badge--danger";
      default:
        return "cc-badge cc-badge--neutral";
    }
  }

  describeScheduleCadence(config) {
    if (config.isScheduled !== true) {
      return "Not scheduled";
    }

    if (config.scheduleCadenceRecognized !== true) {
      return this.formatOptionalTimestamp(
        config.scheduleNextFireTime,
        "Scheduled in Salesforce"
      );
    }

    if (config.scheduleCadenceType === SCHEDULE_CADENCE_MINUTES) {
      const intervalMinutes = Number(config.scheduleIntervalMinutes) || 15;
      return `Every ${intervalMinutes} minute${
        intervalMinutes === 1 ? "" : "s"
      }`;
    }

    if (config.scheduleCadenceType === SCHEDULE_CADENCE_HOURLY) {
      const intervalHours = Number(config.scheduleIntervalHours) || 1;
      const minuteOfHour = Number(config.scheduleMinuteOfHour) || 0;
      return `Every ${intervalHours} hour${
        intervalHours === 1 ? "" : "s"
      } at :${this.padNumber(minuteOfHour)}`;
    }

    if (config.scheduleCadenceType === SCHEDULE_CADENCE_WEEKLY) {
      const dayLabel =
        SCHEDULE_DAY_LABELS[config.scheduleDayOfWeek] || "Unknown day";
      const hourOfDay = Number(config.scheduleHourOfDay) || 0;
      const minuteOfHour = Number(config.scheduleMinuteOfHour) || 0;
      return `${dayLabel} ${this.padNumber(hourOfDay)}:${this.padNumber(
        minuteOfHour
      )}`;
    }

    return "Scheduled in Salesforce";
  }

  padNumber(value) {
    return String(value).padStart(2, "0");
  }

  describeBuilder(builderType) {
    switch (builderType) {
      case "Commerce":
        return "Commerce catalog builder";
      case "Variant":
        return "Variant-aware builder";
      case "Grouping":
        return "Grouping builder";
      case "GroupingWithVariants":
        return "Grouping + variant builder";
      default:
        return this.normalizeText(
          builderType,
          "Default - Simple products without grouping/variant logic"
        );
    }
  }

  describeAccessDestination(
    productSourceId,
    availabilitySourceId,
    buyerGroupAvailabilityMode
  ) {
    const usesPaired = usesPairedSource(buyerGroupAvailabilityMode);
    const usesEmbedded = usesEmbeddedAccess(buyerGroupAvailabilityMode);
    const parts = [];

    if (usesPaired) {
      parts.push(
        this.normalizeText(availabilitySourceId, "Availability source missing")
      );
    }
    if (usesEmbedded) {
      parts.push(
        `${this.normalizeText(productSourceId, "Product source missing")} (embedded)`
      );
    }

    return parts.length ? parts.join(" + ") : "Disabled";
  }

  getConfigCardClass(isSelected) {
    return isSelected
      ? "cc-config-card cc-config-card--selected"
      : "cc-config-card";
  }

  splitCsv(value) {
    return (value || "")
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);
  }

  normalizeText(value, fallback) {
    return value && String(value).trim() ? value : fallback;
  }

  toTimestamp(isoValue) {
    if (!isoValue) {
      return null;
    }

    const timestamp = new Date(isoValue).getTime();
    return Number.isNaN(timestamp) ? null : timestamp;
  }

  formatDuration(durationMs) {
    const totalSeconds = Math.max(0, Math.round((durationMs || 0) / 1000));
    const days = Math.floor(totalSeconds / 86400);
    const hours = Math.floor((totalSeconds % 86400) / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;

    if (days > 0) {
      return `${days}d ${hours}h`;
    }

    if (hours > 0) {
      return `${hours}h ${minutes}m`;
    }

    if (minutes > 0) {
      return `${minutes}m ${seconds}s`;
    }

    return `${seconds}s`;
  }

  formatTimestamp(isoValue) {
    if (!isoValue) {
      return "Just now";
    }

    try {
      return new Intl.DateTimeFormat(undefined, {
        month: "short",
        day: "numeric",
        hour: "numeric",
        minute: "2-digit"
      }).format(new Date(isoValue));
    } catch (error) {
      return isoValue;
    }
  }

  formatOptionalTimestamp(isoValue, fallback) {
    return isoValue ? this.formatTimestamp(isoValue) : fallback;
  }

  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant
      })
    );
  }

  reduceError(error) {
    if (Array.isArray(error?.body)) {
      return error.body.map((item) => item.message).join(", ");
    }
    return error?.body?.message || "Unknown error";
  }
}
