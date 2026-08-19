import { LightningElement, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
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
const SELECTED_CONFIG_STORAGE_KEY = "catalogJobConsoleSelectedConfig:v1";
const WORKSPACE_FOCUS_STORAGE_KEY = "catalogJobConsoleWorkspaceFocus:v1";
const MAX_RUNS = 24;
const MAX_VISIBLE_COMPLETED_RUNS_PER_CONFIG = 3;
const MAX_ACTIVITY_ITEMS = 18;
const ASYNC_APEX_JOBS_SETUP_URL = "/lightning/setup/AsyncApexJobs/home";
const BUYER_GROUP_MODE_DISABLED = "Disabled";
const BUYER_GROUP_MODE_PAIRED = "PairedSource";
const BUYER_GROUP_MODE_EMBEDDED = "Embedded";
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
  return resolvedMode === BUYER_GROUP_MODE_PAIRED;
}

function usesEmbeddedAccess(mode) {
  const resolvedMode = resolveBuyerGroupAvailabilityMode(mode);
  return resolvedMode === BUYER_GROUP_MODE_EMBEDDED;
}

function formatBuyerGroupAvailabilityMode(mode) {
  switch (resolveBuyerGroupAvailabilityMode(mode)) {
    case BUYER_GROUP_MODE_PAIRED:
      return "Paired Source";
    case BUYER_GROUP_MODE_EMBEDDED:
      return "Embedded";
    default:
      return "Disabled";
  }
}

export default class CatalogJobConsole extends NavigationMixin(
  LightningElement
) {
  configs;
  error;
  selectedConfigId;
  workspaceFocus = "status";
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
      this.reconcileTrackedProductRuns();
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

  get selectedConfigMatchedRunSessions() {
    if (!this.selectedConfig) {
      return [];
    }

    const matchingRuns = [];
    const includedRunKeys = new Set();
    const includedJobIds = new Set();

    this.runSessions
      .filter((runSession) => this.runMatchesSelectedConfig(runSession))
      .forEach((runSession) => {
        this.addMatchedRunSession(
          matchingRuns,
          includedRunKeys,
          includedJobIds,
          runSession
        );
      });

    (this.selectedConfig.recentProductRuns || [])
      .filter(
        (recentRun) =>
          (recentRun.configDeveloperName ||
            this.selectedConfig.developerName) ===
          this.selectedConfig.developerName
      )
      .forEach((recentRun) => {
        this.addMatchedRunSession(
          matchingRuns,
          includedRunKeys,
          includedJobIds,
          this.createTrackedProductRunSession(this.selectedConfig, recentRun)
        );
      });

    return matchingRuns.sort(
      (left, right) =>
        this.getRunSessionSortTime(right) - this.getRunSessionSortTime(left)
    );
  }

  get selectedConfigRunSessions() {
    const matchingRuns = this.selectedConfigMatchedRunSessions;
    const activeRuns = matchingRuns.filter(
      (runSession) => !runSession.isTerminal
    );
    const terminalRuns = matchingRuns.filter(
      (runSession) => runSession.isTerminal
    );

    return [
      ...activeRuns,
      ...terminalRuns.slice(0, MAX_VISIBLE_COMPLETED_RUNS_PER_CONFIG)
    ];
  }

  get hasSelectedConfigRunSessions() {
    return this.selectedConfigRunSessions.length > 0;
  }

  get selectedConfigLatestRun() {
    return this.selectedConfigMatchedRunSessions[0] || null;
  }

  get selectedConfigLiveRunCount() {
    return this.selectedConfigMatchedRunSessions.filter(
      (session) => !session.isTerminal
    ).length;
  }

  get selectedConfigTerminalRunCount() {
    return this.selectedConfigMatchedRunSessions.filter(
      (session) => session.isTerminal
    ).length;
  }

  get selectedConfigHiddenTerminalRunCount() {
    return Math.max(
      0,
      this.selectedConfigTerminalRunCount -
        MAX_VISIBLE_COMPLETED_RUNS_PER_CONFIG
    );
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
        label: "Baseline Full Config",
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
        label: "Shared Web Stores",
        value: this.selectedConfig.webStoreIdsLabel
      },
      {
        label: "Pricebooks",
        value: this.selectedConfig.pricebookIdsLabel
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
        label: "Last Successful Full Baseline",
        value: this.selectedConfig.lastSuccessfulFullSyncLabel
      },
      {
        label: "Latest Successful Sync",
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

  get selectedBaselineClarityRows() {
    if (!this.selectedConfig) {
      return [];
    }

    return [
      {
        label: "Latest successful sync",
        value: this.selectedConfig.lastSuccessfulSyncLabel
      },
      {
        label: "Last successful full baseline",
        value: this.selectedConfig.lastSuccessfulFullSyncLabel
      },
      {
        label: "Baseline full config",
        value: this.selectedConfig.baselineFullConfigLabel
      }
    ];
  }

  get selectedConfigMetricCards() {
    if (!this.selectedConfig) {
      return [];
    }

    const latestRun = this.selectedConfigLatestRun;
    const liveRunCount = this.selectedConfigLiveRunCount;

    return [
      {
        label: "Latest Successful Sync",
        value: this.formatMetricMoment(
          this.selectedConfig.lastSuccessfulSyncAt,
          "Never"
        ),
        meta: this.selectedConfig.lastSuccessfulSyncLabel
      },
      {
        label: "Last Full Baseline",
        value: this.formatMetricDate(
          this.selectedConfig.lastSuccessfulFullSyncAt,
          "Never"
        ),
        meta: this.selectedConfig.lastSuccessfulFullSyncLabel
      },
      {
        label: "Tracked Product Job",
        value:
          liveRunCount > 0
            ? `${liveRunCount} live`
            : latestRun
              ? "Recent only"
              : "No runs",
        meta: this.getTrackedProductJobMeta(latestRun)
      }
    ];
  }

  get workspaceNavItems() {
    return [
      {
        value: "status",
        label: "Status",
        className: this.getWorkspaceNavClass("status")
      },
      {
        value: "liveRuns",
        label: "Live Runs",
        className: this.getWorkspaceNavClass("liveRuns")
      },
      {
        value: "activity",
        label: "Activity",
        className: this.getWorkspaceNavClass("activity")
      },
      {
        value: "details",
        label: "Details",
        className: this.getWorkspaceNavClass("details")
      }
    ];
  }

  get isWorkspaceStatusTab() {
    return this.workspaceFocus === "status";
  }

  get isWorkspaceLiveRunsTab() {
    return this.workspaceFocus === "liveRuns";
  }

  get isWorkspaceActivityTab() {
    return this.workspaceFocus === "activity";
  }

  get isWorkspaceDetailsTab() {
    return this.workspaceFocus === "details";
  }

  get selectedConfigRunMonitorSubtitle() {
    if (!this.selectedConfig) {
      return "Choose a configuration to start monitoring targeted runs.";
    }

    if (!this.hasSelectedConfigRunSessions) {
      return "No tracked runs for this configuration yet. Launch one here, or wait for an active Salesforce product job to appear.";
    }

    if (this.selectedConfigLiveRunCount > 0) {
      const hiddenCount = this.selectedConfigHiddenTerminalRunCount;
      return hiddenCount > 0
        ? `Showing all active runs plus ${MAX_VISIBLE_COMPLETED_RUNS_PER_CONFIG} recent completed runs. ${hiddenCount} older completed run${
            hiddenCount === 1 ? " is" : "s are"
          } hidden to keep this view focused.`
        : "Showing all active runs for the selected configuration. Auto-refreshing every 4 seconds while they are in progress.";
    }

    if (this.selectedConfigHiddenTerminalRunCount > 0) {
      const hiddenCount = this.selectedConfigHiddenTerminalRunCount;
      return `Showing ${MAX_VISIBLE_COMPLETED_RUNS_PER_CONFIG} recent completed runs for this configuration. ${hiddenCount} older completed run${
        hiddenCount === 1 ? " is" : "s are"
      } hidden to keep this view focused.`;
    }

    return "Showing recent tracked runs for the selected configuration.";
  }

  get runMonitorSubtitle() {
    if (!this.hasRunSessions) {
      return "Launch a sync here, or wait for an active Salesforce product job to appear.";
    }

    if (this.hasIncompleteRuns) {
      return "Auto-refreshing every 4 seconds while active runs are in progress.";
    }

    return "Recent run history from this console session, plus active product jobs detected in Salesforce.";
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

  get selectedProductStatusFootnote() {
    if (!this.selectedConfig) {
      return "";
    }

    return this.selectedConfig.lastSuccessfulSyncLabel === "Never"
      ? "No successful product sync has been recorded yet."
      : `Latest successful sync: ${this.selectedConfig.lastSuccessfulSyncLabel}`;
  }

  get selectedRunDownloadStatusLabel() {
    return this.selectedConfigLatestRun ? "Ready" : "Waiting";
  }

  get selectedRunDownloadStatusClass() {
    return this.selectedConfigLatestRun
      ? "cc-badge cc-badge--success"
      : "cc-badge cc-badge--neutral";
  }

  get selectedRunSummaryDownloadDisabled() {
    return !this.selectedConfigLatestRun;
  }

  get selectedRunDownloadSummary() {
    const latestRun = this.selectedConfigLatestRun;
    if (!latestRun) {
      return "No tracked run summary is available yet for this configuration.";
    }

    return `${latestRun.overallStatusLabel} • Started ${latestRun.launchedAtLabel}`;
  }

  get selectedRunDownloadMeta() {
    if (!this.selectedConfigLatestRun) {
      return "Launch a sync from this workspace, or wait for an active Salesforce product job to seed the latest run summary here.";
    }

    return "Download a JSON snapshot for the latest tracked run, including job stages, status, progress, and timing.";
  }

  get selectedRunPrimaryStage() {
    const latestRun = this.selectedConfigLatestRun;
    if (!latestRun) {
      return null;
    }

    const stages = latestRun.stages || latestRun.jobs || [];
    return (
      stages.find((stage) => stage.channel === "products" && stage.jobId) ||
      stages.find((stage) => stage.jobId) ||
      null
    );
  }

  get selectedRunAsyncJobId() {
    return this.selectedRunPrimaryStage?.jobId || "";
  }

  get selectedRunAsyncJobDisabled() {
    return !this.selectedRunAsyncJobId;
  }

  get selectedRunAsyncJobSummary() {
    const stage = this.selectedRunPrimaryStage;
    if (!stage) {
      return "No tracked Async Apex job is available yet for this configuration.";
    }

    return `${stage.label} • Job ${stage.jobId}`;
  }

  get selectedRunAsyncJobMeta() {
    if (!this.selectedRunPrimaryStage) {
      return "Launch a sync here, or wait for an active Salesforce product job to seed the latest job reference.";
    }

    return "Open Salesforce Setup with Apex Jobs so the latest tracked platform job is easy to inspect when deeper troubleshooting is needed.";
  }

  get selectedRunAsyncJobSupporting() {
    return this.selectedRunAsyncJobId
      ? "The latest tracked job ID stays visible here so it is quick to cross-check inside Salesforce Setup."
      : "The latest tracked job ID will appear here as soon as this configuration has an active or recent run.";
  }

  get selectedWorkspaceDetailRows() {
    if (!this.selectedConfig) {
      return [];
    }

    return [
      {
        label: "Baseline Full Config",
        value: this.selectedConfig.baselineFullConfigLabel
      },
      {
        label: "Product Source",
        value: this.selectedConfig.productSourceLabel
      },
      {
        label: "Availability Source",
        value: this.selectedConfig.availabilitySourceLabel
      },
      {
        label: "Access Mode",
        value: this.selectedConfig.buyerGroupAvailabilityModeLabel
      },
      {
        label: this.selectedConfig.webStoreIdsLabel !== "No shared stores"
          ? "Shared Web Stores"
          : "Web Store",
        value: this.selectedConfig.webStoreIdsLabel !== "No shared stores"
          ? this.selectedConfig.webStoreIdsLabel
          : this.selectedConfig.webStoreLabel
      },
      {
        label: "Pricebooks",
        value: this.selectedConfig.pricebookIdsLabel
      },
      {
        label: "Scope",
        value: this.selectedConfig.scopeSummary
      },
      {
        label: "Schedule",
        value: this.selectedConfig.scheduleSummary
      },
      {
        label: "Extra Fields",
        value: this.selectedConfig.extraFieldsSummary
      }
    ];
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
    this.workspaceFocus = "status";
    this.configs = this.configs.map((config) =>
      this.decorateConfig(config, this.selectedConfigId)
    );
    this.persistRunState();
  }

  handleSelectWorkspaceFocus(event) {
    const focus = event.currentTarget?.dataset?.focus;
    if (!focus) {
      return;
    }

    this.workspaceFocus = focus;
    this.persistRunState();
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

  handleDownloadRunSummary(event) {
    const runKey = event.currentTarget?.dataset?.runKey;
    if (!runKey) {
      return;
    }

    this.downloadRunSummaryByKey(runKey);
  }

  handleDownloadSelectedRunSummary() {
    const runKey = this.selectedConfigLatestRun?.runKey;
    if (!runKey) {
      this.showToast(
        "Run unavailable",
        "There is no tracked run summary available yet for this configuration.",
        "info"
      );
      return;
    }

    this.downloadRunSummaryByKey(runKey);
  }

  handleOpenSelectedAsyncApexJob() {
    if (!this.selectedRunAsyncJobId) {
      this.showToast(
        "Job unavailable",
        "There is no tracked Async Apex job available yet for this configuration.",
        "info"
      );
      return;
    }

    this.navigateToSetupPage(ASYNC_APEX_JOBS_SETUP_URL);
  }

  downloadRunSummaryByKey(runKey) {
    const runSession = this.findRunSessionByKey(runKey);
    if (!runSession) {
      this.showToast(
        "Run unavailable",
        "The selected run is no longer available in this console session.",
        "warning"
      );
      return;
    }

    const decoratedRun = runSession.stages
      ? runSession
      : this.decorateRunSession(runSession);
    const payload = this.buildRunSummaryExport(decoratedRun);

    try {
      const blob = new Blob([JSON.stringify(payload, null, 2)], {
        type: "application/json"
      });
      const downloadUrl = URL.createObjectURL(blob);
      const downloadLink = document.createElement("a");
      downloadLink.href = downloadUrl;
      downloadLink.download = this.buildRunSummaryFilename(decoratedRun);
      document.body.appendChild(downloadLink);
      downloadLink.click();
      document.body.removeChild(downloadLink);
      window.setTimeout(() => URL.revokeObjectURL(downloadUrl), 0);
    } catch (error) {
      this.showToast(
        "Download failed",
        "Unable to build the run summary.",
        "error"
      );
      // eslint-disable-next-line no-console
      console.error("Download run summary error", error);
    }
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

    this.workspaceFocus = "liveRuns";
    this.persistRunState();
  }

  createRunSession(launch) {
    return {
      runKey: launch.runKey,
      developerName: launch.developerName,
      label: launch.label,
      mode: launch.mode,
      source: "sessionLaunch",
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

  reconcileTrackedProductRuns() {
    if (!Array.isArray(this.configs) || !this.configs.length) {
      return;
    }

    const configByDeveloperName = new Map(
      this.configs.map((config) => [config.developerName, config])
    );
    const trackedRunsByJobId = new Map();

    this.configs.forEach((config) => {
      (config.recentProductRuns || []).forEach((recentRun) => {
        if (!recentRun?.jobId) {
          return;
        }

        const ownerConfig =
          configByDeveloperName.get(recentRun.configDeveloperName) || config;

        trackedRunsByJobId.set(recentRun.jobId, {
          config: ownerConfig,
          recentRun
        });
      });
    });

    if (!trackedRunsByJobId.size) {
      return;
    }

    const knownJobIds = new Set();
    this.runSessions.forEach((runSession) => {
      (runSession.jobs || []).forEach((job) => {
        if (job.jobId) {
          knownJobIds.add(job.jobId);
        }
      });
    });

    const nextRuns = [];
    trackedRunsByJobId.forEach(({ config, recentRun }, jobId) => {
      if (knownJobIds.has(jobId)) {
        return;
      }

      knownJobIds.add(jobId);
      nextRuns.push(this.createTrackedProductRunSession(config, recentRun));
    });

    if (!nextRuns.length) {
      return;
    }

    nextRuns.forEach((runSession) => {
      if (runSession.jobs?.[0]?.isTerminal === true) {
        return;
      }

      const trackedJobId = runSession.jobs?.[0]?.jobId;
      this.addActivity(
        `${runSession.label}: tracking active Salesforce product job${
          trackedJobId ? ` ${trackedJobId}` : ""
        }`
      );
    });

    this.runSessions = [...nextRuns, ...this.runSessions]
      .slice(0, MAX_RUNS)
      .map((session) => this.decorateRunSession(session));

    this.persistRunState();
    this.startPollingIfNeeded();
  }

  createTrackedProductRunSession(config, recentRun = null) {
    const runMode =
      recentRun?.runMode === SYNC_MODE_DELTA ||
      config.currentProductRunMode === SYNC_MODE_DELTA
        ? SYNC_MODE_DELTA
        : SYNC_MODE_FULL;
    const launchedAt =
      recentRun?.startedAt ||
      config.currentProductStartedAt ||
      new Date().toISOString();
    const jobId = recentRun?.jobId || config.currentProductJobId;
    const status =
      recentRun?.status || config.currentProductJobStatus || "Queued";
    const completedAt = recentRun?.completedAt || null;
    const isTerminal = recentRun?.isTerminal === true;

    return {
      runKey: `tracked-${jobId}`,
      developerName:
        recentRun?.configDeveloperName ||
        config.currentProductConfigDeveloperName ||
        config.developerName,
      label: config.label,
      mode: "products",
      source: "trackedProductJob",
      availabilityEnabled: config.buyerGroupAccessEnabled === true,
      buyerGroupAvailabilityMode: config.buyerGroupAvailabilityMode,
      launchedAt,
      jobs: [
        {
          jobId,
          channel: "products",
          label:
            runMode === SYNC_MODE_DELTA
              ? "Delta Product Sync"
              : "Full Product Sync",
          impactedProductCount: undefined,
          changedRootProductCount: undefined,
          exportProductCount: undefined,
          scopeSummary: "",
          status,
          jobItemsProcessed: 0,
          totalJobItems: 0,
          numberOfErrors: 0,
          extendedStatus: "",
          isTerminal,
          createdDate: launchedAt,
          completedDate: completedAt
        }
      ]
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
      window.sessionStorage.setItem(
        SELECTED_CONFIG_STORAGE_KEY,
        this.selectedConfigId || ""
      );
      window.sessionStorage.setItem(
        WORKSPACE_FOCUS_STORAGE_KEY,
        this.workspaceFocus || "status"
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
      const storedSelectedConfig = window.sessionStorage.getItem(
        SELECTED_CONFIG_STORAGE_KEY
      );
      const storedWorkspaceFocus = window.sessionStorage.getItem(
        WORKSPACE_FOCUS_STORAGE_KEY
      );

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

      if (storedSelectedConfig) {
        this.selectedConfigId = storedSelectedConfig;
      }

      if (storedWorkspaceFocus) {
        this.workspaceFocus = storedWorkspaceFocus;
      }
    } catch (error) {
      this.runSessions = [];
      this.activityFeed = [];
    }
  }

  navigateToSetupPage(url) {
    if (!url) {
      return;
    }

    const pageReference = {
      type: "standard__webPage",
      attributes: {
        url
      }
    };

    this[NavigationMixin.GenerateUrl](pageReference)
      .then((generatedUrl) => {
        const openedWindow = window.open(
          generatedUrl || url,
          "_blank",
          "noopener"
        );

        if (!openedWindow) {
          this[NavigationMixin.Navigate](pageReference);
        }
      })
      .catch(() => {
        this[NavigationMixin.Navigate](pageReference);
      });
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
      webStoreIdsLabel: this.describeIdScope(
        config.WebStoreIds__c,
        "No shared stores"
      ),
      pricebookIdsLabel: this.describeIdScope(
        config.PricebookIds__c,
        config.WebStoreIds__c
          ? "Resolved from shared stores"
          : "All active pricebooks"
      ),
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
      recentProductRuns: this.normalizeRecentProductRuns(
        config.recentProductRuns,
        config.DeveloperName
      ),
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
      inventoryLastSyncMeta: `Last successful full baseline: ${this.formatOptionalTimestamp(
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
    const primaryDetail = scopeSummary || job.extendedStatus || batchesLabel;
    const secondaryDetail =
      scopeSummary && batchesLabel && batchesLabel !== scopeSummary
        ? batchesLabel
        : "";

    return {
      ...job,
      status,
      progressPercent,
      statusLabel: this.describeStageStatusBadge(status),
      statusClass: this.getStageStatusClass(status),
      batchesLabel,
      extendedStatus: scopeSummary || job.extendedStatus || "",
      primaryDetail,
      secondaryDetail,
      timingLabel: this.describeStageDuration(job),
      canAbort:
        !!job.jobId &&
        status !== "Completed" &&
        status !== "Failed" &&
        status !== "Aborted"
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

  describeStageStatusBadge(status) {
    switch (status) {
      case "Holding":
      case "Preparing":
        return "Queued";
      default:
        return this.normalizeText(status, "Queued");
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
      const scheduleStateLabel = this.describeScheduleState(
        config.scheduleState
      );
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

  getTrackedProductJobMeta(latestRun) {
    if (this.selectedConfig?.currentProductIsActive === true) {
      return this.selectedConfig.currentProductJobId
        ? `Job ${this.selectedConfig.currentProductJobId}`
        : "Active product job detected";
    }

    if (latestRun) {
      return `Latest tracked run started ${latestRun.launchedAtLabel}`;
    }

    return "Waiting for launch";
  }

  getWorkspaceNavClass(focus) {
    return focus === this.workspaceFocus
      ? "cc-workspace-nav__button cc-workspace-nav__button--active"
      : "cc-workspace-nav__button";
  }

  addMatchedRunSession(
    matchingRuns,
    includedRunKeys,
    includedJobIds,
    runSession
  ) {
    if (!runSession) {
      return;
    }

    const decoratedRun = runSession.stages
      ? runSession
      : this.decorateRunSession(runSession);
    const jobIds = (decoratedRun.jobs || [])
      .map((job) => job.jobId)
      .filter(Boolean);
    const runKey = jobIds.length
      ? jobIds.join("|")
      : decoratedRun.runKey || null;

    if (jobIds.some((jobId) => includedJobIds.has(jobId))) {
      return;
    }

    if (!jobIds.length && runKey && includedRunKeys.has(runKey)) {
      return;
    }

    matchingRuns.push(decoratedRun);
    jobIds.forEach((jobId) => includedJobIds.add(jobId));
    if (runKey) {
      includedRunKeys.add(runKey);
    }
  }

  getRunSessionSortTime(runSession) {
    return this.toTimestamp(runSession?.launchedAt) ?? 0;
  }

  findRunSessionByKey(runKey) {
    if (!runKey) {
      return null;
    }

    return (
      this.runSessions.find((run) => run.runKey === runKey) ||
      this.selectedConfigMatchedRunSessions.find(
        (run) => run.runKey === runKey
      ) ||
      null
    );
  }

  runMatchesSelectedConfig(runSession) {
    if (!this.selectedConfig || !runSession) {
      return false;
    }

    return runSession.developerName === this.selectedConfig.developerName;
  }

  splitCsv(value) {
    return (value || "")
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);
  }

  describeIdScope(value, fallback) {
    const values = this.splitCsv(value);
    return values.length
      ? `${values.length} configured: ${values.join(", ")}`
      : fallback;
  }

  normalizeText(value, fallback) {
    return value && String(value).trim() ? value : fallback;
  }

  normalizeRecentProductRuns(recentProductRuns, defaultDeveloperName) {
    if (!Array.isArray(recentProductRuns)) {
      return [];
    }

    return recentProductRuns
      .filter((recentRun) => recentRun?.jobId)
      .map((recentRun) => ({
        ...recentRun,
        jobId: recentRun.jobId,
        runMode:
          recentRun.runMode === SYNC_MODE_DELTA
            ? SYNC_MODE_DELTA
            : SYNC_MODE_FULL,
        configDeveloperName:
          recentRun.configDeveloperName || defaultDeveloperName,
        status: recentRun.status || "Queued",
        startedAt: recentRun.startedAt || null,
        completedAt: recentRun.completedAt || null,
        isTerminal: recentRun.isTerminal === true
      }));
  }

  formatMetricMoment(isoValue, fallback) {
    if (!isoValue) {
      return fallback;
    }

    const date = new Date(isoValue);
    if (Number.isNaN(date.getTime())) {
      return fallback;
    }

    const now = new Date();
    const sameDay = date.toDateString() === now.toDateString();

    return new Intl.DateTimeFormat(undefined, {
      ...(sameDay
        ? {
            hour: "numeric",
            minute: "2-digit"
          }
        : {
            month: "short",
            day: "numeric"
          })
    }).format(date);
  }

  formatMetricDate(isoValue, fallback) {
    if (!isoValue) {
      return fallback;
    }

    const date = new Date(isoValue);
    if (Number.isNaN(date.getTime())) {
      return fallback;
    }

    return new Intl.DateTimeFormat(undefined, {
      month: "short",
      day: "numeric"
    }).format(date);
  }

  buildRunSummaryExport(runSession) {
    return {
      exportedAt: new Date().toISOString(),
      runKey: runSession.runKey,
      label: runSession.label,
      developerName: runSession.developerName,
      mode: runSession.mode,
      source: runSession.source || "sessionLaunch",
      availabilityEnabled: runSession.availabilityEnabled === true,
      buyerGroupAvailabilityMode: runSession.buyerGroupAvailabilityMode || "",
      launchedAt: runSession.launchedAt || null,
      launchedAtLabel:
        runSession.launchedAtLabel ||
        this.formatTimestamp(runSession.launchedAt),
      overallStatusLabel: runSession.overallStatusLabel || "",
      progressPercent: runSession.progressPercent ?? null,
      isTerminal: runSession.isTerminal === true,
      jobs: (runSession.stages || runSession.jobs || []).map((job) => ({
        jobId: job.jobId || "",
        channel: job.channel || "",
        label: job.label || "",
        status: job.status || "",
        statusLabel: job.statusLabel || "",
        progressPercent: job.progressPercent ?? null,
        jobItemsProcessed: job.jobItemsProcessed ?? null,
        totalJobItems: job.totalJobItems ?? null,
        numberOfErrors: job.numberOfErrors ?? null,
        batchesLabel: job.batchesLabel || "",
        extendedStatus: job.extendedStatus || "",
        timingLabel: job.timingLabel || "",
        impactedProductCount: job.impactedProductCount ?? null,
        changedRootProductCount: job.changedRootProductCount ?? null,
        exportProductCount: job.exportProductCount ?? null,
        scopeSummary: job.scopeSummary || "",
        createdDate: job.createdDate || null,
        completedDate: job.completedDate || null
      }))
    };
  }

  buildRunSummaryFilename(runSession) {
    const fileStem = this.sanitizeFileSegment(
      runSession.developerName || runSession.label || "catalog-run"
    );
    const timestamp = this.buildFileTimestamp(
      runSession.launchedAt || new Date().toISOString()
    );
    return `${fileStem}-${timestamp}.json`;
  }

  sanitizeFileSegment(value) {
    return (
      String(value || "catalog-run")
        .trim()
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "") || "catalog-run"
    );
  }

  buildFileTimestamp(isoValue) {
    const date = isoValue ? new Date(isoValue) : new Date();
    if (Number.isNaN(date.getTime())) {
      return "run-summary";
    }

    return [
      date.getFullYear(),
      this.padNumber(date.getMonth() + 1),
      this.padNumber(date.getDate()),
      "-",
      this.padNumber(date.getHours()),
      this.padNumber(date.getMinutes()),
      this.padNumber(date.getSeconds())
    ].join("");
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
