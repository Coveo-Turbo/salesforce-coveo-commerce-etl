import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

import listConfigs from "@salesforce/apex/CatalogJobRunner.listConfigs";
import runSingle from "@salesforce/apex/CatalogJobRunner.runSingle";
import runSingleAvailability from "@salesforce/apex/CatalogJobRunner.runSingleAvailability";
import runSingleBoth from "@salesforce/apex/CatalogJobRunner.runSingleBoth";
import runAllActive from "@salesforce/apex/CatalogJobRunner.runAllActive";
import runAllActiveAvailability from "@salesforce/apex/CatalogJobRunner.runAllActiveAvailability";
import runAllActiveBoth from "@salesforce/apex/CatalogJobRunner.runAllActiveBoth";
import getRunSnapshots from "@salesforce/apex/CatalogJobRunner.getRunSnapshots";

const POLL_INTERVAL_MS = 4000;
const RUN_STORAGE_KEY = "catalogJobConsoleRuns:v1";
const ACTIVITY_STORAGE_KEY = "catalogJobConsoleActivity:v1";
const MAX_RUNS = 8;
const MAX_ACTIVITY_ITEMS = 18;

export default class CatalogJobConsole extends LightningElement {
  configs;
  error;
  selectedConfigId;
  runSessions = [];
  activityFeed = [];
  pollTimerId;
  isPolling = false;

  connectedCallback() {
    this.restoreRunState();
    this.startPollingIfNeeded();
  }

  disconnectedCallback() {
    this.stopPolling();
  }

  @wire(listConfigs)
  wiredConfigs({ data, error }) {
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

  get totalJobs() {
    return this.configs ? this.configs.length : 0;
  }

  get activeJobs() {
    return this.configs
      ? this.configs.filter((config) => config.IsActive__c).length
      : 0;
  }

  get availabilityReadyJobs() {
    return this.configs
      ? this.configs.filter((config) => config.EnableBuyerGroupAvailability__c)
          .length
      : 0;
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
      return "Choose a configuration to launch products or availability syncs.";
    }
    return `${this.selectedConfig.catalogLabel} • ${this.selectedConfig.localeLabel} • ${this.selectedConfig.builderLabel}`;
  }

  get availabilityDisabledMessage() {
    if (this.selectedConfig?.EnableBuyerGroupAvailability__c) {
      return "";
    }
    return "Buyer Group availability is disabled for this configuration.";
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
      `${this.selectedConfig.label}: started product sync`
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
      `${this.selectedConfig.label}: started availability sync`
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
      `${this.selectedConfig.label}: started products and availability syncs`
    );
  }

  async handleRunAllProducts() {
    await this.launchRuns(
      () => runAllActive(),
      "Started product syncs for all active configurations"
    );
  }

  async handleRunAllAvailability() {
    await this.launchRuns(
      () => runAllActiveAvailability(),
      "Started availability syncs for active Buyer Group-enabled configurations"
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
        `${launch.label}: ${this.describeLaunchMode(launch.mode)} started`
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
      launchedAt: launch.launchedAt,
      jobs: (launch.jobs || []).map((job) => ({
        jobId: job.jobId,
        channel: job.channel,
        label: job.label,
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
          ...snapshot
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

    return {
      ...config,
      id: config.DeveloperName,
      developerName: config.DeveloperName,
      label: config.Label,
      cardClass: this.getConfigCardClass(isSelected),
      catalogLabel: this.normalizeText(config.CatalogId__c, "Catalog not set"),
      localeLabel: this.normalizeText(config.Locale__c, "Default locale"),
      builderLabel: this.normalizeText(config.BuilderType__c, "Default"),
      builderSummary: this.describeBuilder(config.BuilderType__c),
      productSourceLabel: this.normalizeText(
        config.SourceId__c,
        "No product source"
      ),
      availabilitySourceLabel: config.EnableBuyerGroupAvailability__c
        ? this.normalizeText(
            config.AvailabilitySourceId__c,
            "Availability source missing"
          )
        : "Not enabled",
      webStoreLabel: config.EnableBuyerGroupAvailability__c
        ? this.normalizeText(config.WebStoreId__c, "Web store missing")
        : "Not required",
      scopeSummary: filterText,
      extraFieldsSummary: extraFields.length
        ? `${extraFields.length} extra field${extraFields.length === 1 ? "" : "s"}`
        : "No extra fields",
      extraFieldsTitle: extraFields.length
        ? extraFields.join(", ")
        : "No extra fields",
      activeStatusLabel: config.IsActive__c ? "Active" : "Inactive",
      activeStatusClass: config.IsActive__c
        ? "cc-badge cc-badge--success"
        : "cc-badge cc-badge--neutral",
      availabilityStatusLabel: config.EnableBuyerGroupAvailability__c
        ? "Availability On"
        : "Availability Off",
      availabilityStatusClass: config.EnableBuyerGroupAvailability__c
        ? "cc-badge cc-badge--info"
        : "cc-badge cc-badge--neutral",
      availabilityDisabled: config.EnableBuyerGroupAvailability__c !== true
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
    const batchesLabel =
      job.totalJobItems > 0
        ? `${job.jobItemsProcessed || 0} / ${job.totalJobItems} batches`
        : "Waiting for batch metrics";

    return {
      ...job,
      status,
      progressPercent,
      statusLabel: this.describeStageChange(job.channel, status),
      statusClass: this.getStageStatusClass(status),
      batchesLabel,
      timingLabel: this.describeStageDuration(job)
    };
  }

  getRunStartTime(runSession, stages) {
    const timestamps = [runSession.launchedAt, ...stages.map((stage) => stage.createdDate)]
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

  describeLaunchMode(mode) {
    switch (mode) {
      case "availability":
        return "availability sync";
      case "both":
        return "product and availability syncs";
      default:
        return "product sync";
    }
  }

  describeStageChange(channel, status) {
    const subject =
      channel === "availability" ? "Syncing availability" : "Syncing products";

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
