import { LightningElement, wire, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";

import getNamedCredentialStatus from "@salesforce/apex/CoveoCommerceSetupController.getNamedCredentialStatus";
import getCatalogJobConfigs from "@salesforce/apex/CoveoCommerceSetupController.getCatalogJobConfigs";
import getActiveBuilderMapping from "@salesforce/apex/CoveoCommerceSetupController.getActiveBuilderMapping";
import getBuilderClassOptions from "@salesforce/apex/CoveoCommerceSetupController.getBuilderClassOptions";
import getSetupWorkspaceOptions from "@salesforce/apex/CoveoCommerceSetupController.getSetupWorkspaceOptions";
import previewMultiStoreCatalogJobDraft from "@salesforce/apex/CoveoCommerceSetupController.previewMultiStoreCatalogJobDraft";
import saveCatalogJobSchedule from "@salesforce/apex/CoveoCommerceSetupController.saveCatalogJobSchedule";
import saveCatalogChainSchedule from "@salesforce/apex/CoveoCommerceSetupController.saveCatalogChainSchedule";
import testNamedCredentialConnection from "@salesforce/apex/CoveoCommerceSetupController.testNamedCredentialConnection";
import clearCatalogJobSchedule from "@salesforce/apex/CoveoCommerceSetupController.clearCatalogJobSchedule";
import clearCatalogChainSchedule from "@salesforce/apex/CoveoCommerceSetupController.clearCatalogChainSchedule";
import validateBuilderClass from "@salesforce/apex/CoveoCommerceSetupController.validateBuilderClass";

const TRUNCATE_LENGTH = 50;
const PREVIEW_DEBOUNCE_MS = 350;
const CONFIG_REFRESH_INTERVAL_MS = 15000;
const BUYER_GROUP_MODE_DISABLED = "Disabled";
const BUYER_GROUP_MODE_PAIRED = "PairedSource";
const BUYER_GROUP_MODE_EMBEDDED = "Embedded";
const SYNC_MODE_FULL = "Full";
const SYNC_MODE_DELTA = "Delta";
const SYNC_MODE_OPTIONS = Object.freeze([
  { label: "Full", value: SYNC_MODE_FULL },
  { label: "Delta", value: SYNC_MODE_DELTA }
]);
const SCHEDULE_CADENCE_MINUTES = "Minutes";
const SCHEDULE_CADENCE_HOURLY = "Hourly";
const SCHEDULE_CADENCE_WEEKLY = "Weekly";
const SCHEDULE_CADENCE_OPTIONS = Object.freeze([
  { label: "Minutes", value: SCHEDULE_CADENCE_MINUTES },
  { label: "Hourly", value: SCHEDULE_CADENCE_HOURLY },
  { label: "Weekly", value: SCHEDULE_CADENCE_WEEKLY }
]);
const SCHEDULE_DAY_OPTIONS = Object.freeze([
  { label: "Sunday", value: "SUN" },
  { label: "Monday", value: "MON" },
  { label: "Tuesday", value: "TUE" },
  { label: "Wednesday", value: "WED" },
  { label: "Thursday", value: "THU" },
  { label: "Friday", value: "FRI" },
  { label: "Saturday", value: "SAT" }
]);
const SCHEDULE_DAY_LABELS = Object.freeze(
  SCHEDULE_DAY_OPTIONS.reduce((labels, option) => {
    labels[option.value] = option.label;
    return labels;
  }, {})
);
const BUYER_GROUP_MODE_OPTIONS = Object.freeze([
  { label: "Disabled", value: BUYER_GROUP_MODE_DISABLED },
  { label: "Paired Source", value: BUYER_GROUP_MODE_PAIRED },
  { label: "Embedded", value: BUYER_GROUP_MODE_EMBEDDED }
]);

const DEFAULT_DRAFT = Object.freeze({
  label: "",
  developerName: "",
  coveoOrgId: "",
  sourceId: "",
  availabilitySourceId: "",
  syncMode: SYNC_MODE_FULL,
  baselineFullConfigDeveloperName: "",
  locale: "en-US",
  catalogId: "",
  webStoreId: "",
  webStoreIds: [],
  pricebookIds: [],
  builderType: "",
  buyerGroupAvailabilityMode: BUYER_GROUP_MODE_DISABLED,
  productFilter: "",
  additionalProductFields: []
});

const DEFAULT_PREVIEW = Object.freeze({
  estimatedProductCount: 0,
  buyerGroupCount: 0,
  selectedFieldCount: 0,
  validationMessages: [],
  warningMessages: [],
  isReady: false
});

const LOCALE_OPTIONS = [
  { label: "English (United States)", value: "en-US" },
  { label: "English (Canada)", value: "en-CA" },
  { label: "French (Canada)", value: "fr-CA" },
  { label: "French (France)", value: "fr-FR" },
  { label: "German (Germany)", value: "de-DE" }
];

const STANDARD_BUILDER_CLASS_NAMES = new Set([
  "CatalogJsonBuilderDefault",
  "CatalogJsonBuilderCommerce",
  "CatalogJsonBuilderGrouping",
  "CatalogJsonBuilderVariant",
  "CatalogJsonBuilderGroupingWithVariants"
]);

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

function resolveSyncMode(mode) {
  return mode === SYNC_MODE_DELTA ? SYNC_MODE_DELTA : SYNC_MODE_FULL;
}

function padNumber(value) {
  return String(value).padStart(2, "0");
}

function getDefaultScheduleCadenceType(syncMode) {
  return resolveSyncMode(syncMode) === SYNC_MODE_DELTA
    ? SCHEDULE_CADENCE_HOURLY
    : SCHEDULE_CADENCE_WEEKLY;
}

export default class CoveoCommerceSetup extends NavigationMixin(
  LightningElement
) {
  @track activeWorkspace = "catalogJobs";
  @track credentialStatus = null;
  @track isLoadingCredential = true;
  @track isTestingConnection = false;
  @track connectionTestResult = null;

  @track rawCatalogConfigs = [];
  @track catalogConfigs = null;
  @track isLoadingConfigs = true;
  @track selectedConfigRow = null;

  @track builderMapping = null;
  @track builderOptions = null;
  @track isLoadingBuilder = true;
  @track customBuilderInput = "";
  @track isValidatingBuilder = false;
  @track builderValidationResult = null;

  @track workspaceOptions = {
    webStores: [],
    pricebooks: [],
    productCatalogs: [],
    builderTypeOptions: [],
    productFieldOptions: []
  };
  @track isLoadingWorkspaceOptions = true;
  @track draft = { ...DEFAULT_DRAFT };
  @track draftPreview = { ...DEFAULT_PREVIEW };
  @track isLoadingDraftPreview = false;
  @track scheduleDraft = null;
  @track isSavingSchedule = false;
  @track isClearingSchedule = false;
  @track chainDraft = {
    chainName: "Shared Catalog",
    configDeveloperNames: [],
    includeAvailability: false
  };
  @track isSavingChainSchedule = false;
  @track isClearingChainSchedule = false;
  @track detailAccordionOpenSections = ["summary"];

  namedCredentialSetupUrl = "/lightning/setup/NamedCredential/home";
  customMetadataSetupUrl = "/lightning/setup/CustomMetadata/home";
  previewRefreshTimeout;
  configRefreshTimerId;
  wiredConfigsResult;
  isRefreshingCatalogConfigs = false;
  scheduleDraftConfigId;

  connectedCallback() {
    this.startCatalogConfigRefresh();
  }

  @wire(getNamedCredentialStatus)
  wiredCredentialStatus({ data, error }) {
    this.isLoadingCredential = false;
    if (data) {
      this.credentialStatus = data;
    } else if (error) {
      this.credentialStatus = { exists: false, status: "Error loading status" };
      // eslint-disable-next-line no-console
      console.error("Error loading credential status:", error);
    }
  }

  @wire(getCatalogJobConfigs)
  wiredConfigs(result) {
    this.wiredConfigsResult = result;
    const { data, error } = result;
    this.isLoadingConfigs = false;
    if (data) {
      this.rawCatalogConfigs = data;
      this.refreshCatalogConfigs();
    } else if (error) {
      this.rawCatalogConfigs = [];
      this.catalogConfigs = [];
      // eslint-disable-next-line no-console
      console.error("Error loading configs:", error);
    }
  }

  @wire(getActiveBuilderMapping)
  wiredBuilderMapping({ data, error }) {
    this.isLoadingBuilder = false;
    if (data) {
      this.builderMapping = data;
    } else if (error) {
      this.builderMapping = {
        className: "CatalogJsonBuilderCommerce",
        isDefault: true
      };
      // eslint-disable-next-line no-console
      console.error("Error loading builder mapping:", error);
    }
  }

  @wire(getBuilderClassOptions)
  wiredBuilderOptions({ data, error }) {
    if (data) {
      this.builderOptions = data;
      this.refreshCatalogConfigs();
    } else if (error) {
      this.builderOptions = [];
      // eslint-disable-next-line no-console
      console.error("Error loading builder options:", error);
    }
  }

  @wire(getSetupWorkspaceOptions)
  wiredWorkspaceOptions({ data, error }) {
    this.isLoadingWorkspaceOptions = false;
    if (data) {
      this.workspaceOptions = {
        webStores: data.webStores || [],
        productCatalogs: data.productCatalogs || [],
        pricebooks: data.pricebooks || [],
        builderTypeOptions: data.builderTypeOptions || [],
        productFieldOptions: data.productFieldOptions || []
      };
      this.refreshCatalogConfigs();
    } else if (error) {
      this.workspaceOptions = {
        webStores: [],
        productCatalogs: [],
        pricebooks: [],
        builderTypeOptions: [],
        productFieldOptions: []
      };
      // eslint-disable-next-line no-console
      console.error("Error loading workspace options:", error);
    }
  }

  disconnectedCallback() {
    window.clearTimeout(this.previewRefreshTimeout);
    this.stopCatalogConfigRefresh();
  }

  async handleRefreshCatalogJobs() {
    await this.refreshCatalogJobConfigs();
  }

  get credentialStatusLabel() {
    return this.credentialStatus?.status || "Unknown";
  }

  get credentialStatusClass() {
    if (this.credentialStatus?.exists) {
      return "slds-badge slds-theme_success";
    }
    if (this.credentialStatus?.status === "API Key Missing") {
      return "slds-badge slds-theme_warning";
    }
    return "slds-badge slds-theme_error";
  }

  get credentialEndpoint() {
    return this.credentialStatus?.endpoint || "Not configured";
  }

  get connectionTestClass() {
    const base = "slds-m-top_small slds-p-around_x-small slds-border_left ";
    if (this.connectionTestResult?.success) {
      return base + "connection-success";
    }
    return base + "connection-error";
  }

  get connectionTestIcon() {
    return this.connectionTestResult?.success
      ? "utility:success"
      : "utility:error";
  }

  get connectionTestMessage() {
    return this.connectionTestResult?.message || "";
  }

  get hasConfigs() {
    return (
      !this.isLoadingConfigs &&
      this.catalogConfigs &&
      this.catalogConfigs.length > 0
    );
  }

  get noConfigs() {
    return (
      !this.isLoadingConfigs &&
      (!this.catalogConfigs || this.catalogConfigs.length === 0)
    );
  }

  get totalConfigs() {
    return this.catalogConfigs ? this.catalogConfigs.length : 0;
  }

  get fullSyncConfigs() {
    return this.catalogConfigs
      ? this.catalogConfigs.filter(
          (config) => config.syncMode !== SYNC_MODE_DELTA
        ).length
      : 0;
  }

  get deltaSyncConfigs() {
    return this.catalogConfigs
      ? this.catalogConfigs.filter(
          (config) => config.syncMode === SYNC_MODE_DELTA
        ).length
      : 0;
  }

  get scheduledConfigs() {
    return this.catalogConfigs
      ? this.catalogConfigs.filter((config) => config.isScheduled).length
      : 0;
  }

  get inventoryTableRows() {
    if (!this.catalogConfigs?.length) {
      return [];
    }

    return [...this.catalogConfigs].sort((left, right) => {
      if (left.syncMode !== right.syncMode) {
        return left.syncMode === SYNC_MODE_FULL ? -1 : 1;
      }
      if (left.isActive !== right.isActive) {
        return left.isActive ? -1 : 1;
      }
      return (left.label || "").localeCompare(right.label || "");
    });
  }

  get availabilityEnabledConfigs() {
    return this.catalogConfigs
      ? this.catalogConfigs.filter(
          (config) => config.buyerGroupAvailabilityEnabled
        ).length
      : 0;
  }

  get activeConfigs() {
    return this.catalogConfigs
      ? this.catalogConfigs.filter((config) => config.isActive).length
      : 0;
  }

  get inactiveConfigs() {
    return this.catalogConfigs
      ? this.catalogConfigs.filter((config) => !config.isActive).length
      : 0;
  }

  get isOverviewView() {
    return this.activeWorkspace === "overview";
  }

  get isConnectionView() {
    return this.activeWorkspace === "connection";
  }

  get isCatalogJobsView() {
    return this.activeWorkspace === "catalogJobs";
  }

  get isAdvancedView() {
    return this.activeWorkspace === "advanced";
  }

  get overviewNavClass() {
    return this.getWorkspaceNavClass("overview");
  }

  get connectionNavClass() {
    return this.getWorkspaceNavClass("connection");
  }

  get catalogJobsNavClass() {
    return this.getWorkspaceNavClass("catalogJobs");
  }

  get advancedNavClass() {
    return this.getWorkspaceNavClass("advanced");
  }

  get workspaceConnectionStatusText() {
    if (this.isLoadingCredential) {
      return "Checking connection";
    }
    return this.credentialStatus?.exists ? "Connected" : "Needs setup";
  }

  get workspaceConnectionSummary() {
    if (this.isLoadingCredential) {
      return "Loading Named Credential status.";
    }
    if (this.credentialStatus?.exists) {
      return `Named Credential is configured for ${this.credentialEndpoint}.`;
    }
    return "Named Credential still needs to be configured before exports can run.";
  }

  get workspaceCatalogSummary() {
    if (!this.totalConfigs) {
      return "No catalog job configs created yet.";
    }
    return `${this.activeConfigs} active configs, ${this.availabilityEnabledConfigs} access-enabled.`;
  }

  get workspaceOverviewHighlights() {
    return [
      {
        key: "connection",
        label: "Connection",
        value: this.workspaceConnectionStatusText,
        helper: this.workspaceConnectionSummary,
        actionLabel: "Open Connection",
        target: "connection"
      },
      {
        key: "catalogJobs",
        label: "Catalog Jobs",
        value: `${this.totalConfigs}`,
        helper: this.workspaceCatalogSummary,
        actionLabel: "Open Catalog Jobs",
        target: "catalogJobs"
      },
      {
        key: "advanced",
        label: "Builder Strategy",
        value: this.builderClassName,
        helper:
          "Review the global builder mapping and validate any custom builder classes.",
        actionLabel: "Open Advanced",
        target: "advanced"
      }
    ];
  }

  get hasSelectedConfig() {
    return Boolean(this.selectedConfigRow);
  }

  get selectedConfigId() {
    return this.selectedConfigRow?.id || "";
  }

  get builderClassName() {
    return this.builderMapping?.className || "CatalogJsonBuilderCommerce";
  }

  get isDefaultBuilder() {
    return this.builderMapping?.isDefault !== false;
  }

  get builderValidationClass() {
    const base = "slds-m-top_small slds-p-around_x-small slds-border_left ";
    if (this.builderValidationResult?.isValid) {
      return base + "validation-success";
    }
    return base + "validation-error";
  }

  get builderValidationIcon() {
    return this.builderValidationResult?.isValid
      ? "utility:success"
      : "utility:error";
  }

  get builderValidationMessage() {
    return this.builderValidationResult?.message || "";
  }

  get localeOptions() {
    return LOCALE_OPTIONS;
  }

  get builderTypeOptions() {
    const workspaceOptions = (
      this.workspaceOptions.builderTypeOptions || []
    ).map((option) => ({
      label: option.label,
      value: option.value
    }));
    const customMappedOptions = (this.builderOptions || [])
      .filter((option) => !STANDARD_BUILDER_CLASS_NAMES.has(option.value))
      .map((option) => ({
        label:
          option.label === option.value
            ? option.label
            : `${option.label} (${option.value})`,
        value: option.value
      }));
    const mergedOptions = [
      { label: "Use Global Default", value: "" },
      ...workspaceOptions,
      ...customMappedOptions
    ];
    const hasCurrentValue = mergedOptions.some(
      (option) => option.value === this.draft.builderType
    );

    if (this.draft.builderType && !hasCurrentValue) {
      mergedOptions.push({
        label: `Custom Class (${this.draft.builderType})`,
        value: this.draft.builderType
      });
    }

    return [...mergedOptions];
  }

  get catalogOptions() {
    return (this.workspaceOptions.productCatalogs || []).map((option) => ({
      label: option.label,
      value: option.value
    }));
  }

  get webStoreOptions() {
    return (this.workspaceOptions.webStores || []).map((option) => ({
      label: option.label,
      value: option.value
    }));
  }

  get pricebookOptions() {
    return (this.workspaceOptions.pricebooks || []).map((option) => ({
      label: option.label,
      value: option.value
    }));
  }

  get productFieldOptions() {
    return (this.workspaceOptions.productFieldOptions || []).map((option) => ({
      label: option.label,
      value: option.value
    }));
  }

  get buyerGroupAvailabilityModeOptions() {
    return BUYER_GROUP_MODE_OPTIONS;
  }

  get syncModeOptions() {
    return SYNC_MODE_OPTIONS;
  }

  get scheduleCadenceOptions() {
    return SCHEDULE_CADENCE_OPTIONS;
  }

  get scheduleDayOptions() {
    return SCHEDULE_DAY_OPTIONS;
  }

  get chainConfigOptions() {
    const selectedMode = this.selectedConfigRow?.syncMode;
    return (this.catalogConfigs || [])
      .filter((config) => config.isActive && config.syncMode === selectedMode)
      .map((config) => ({
        label: `${config.label} (${config.developerName})`,
        value: config.developerName
      }));
  }

  get chainNameValue() {
    return this.chainDraft?.chainName || "Shared Catalog";
  }

  get chainConfigDeveloperNames() {
    return this.chainDraft?.configDeveloperNames || [];
  }

  get chainIncludeAvailability() {
    return this.chainDraft?.includeAvailability === true;
  }

  get isChainScheduleSaveDisabled() {
    return (
      this.isSavingChainSchedule ||
      !this.selectedConfigRow ||
      !this.chainNameValue.trim() ||
      !this.chainConfigDeveloperNames.length
    );
  }

  get isChainScheduleClearDisabled() {
    return this.isClearingChainSchedule || !this.chainNameValue.trim();
  }

  get hasWorkspaceOptions() {
    return !this.isLoadingWorkspaceOptions;
  }

  get availabilityToggleLabel() {
    return `Buyer Group Access: ${this.selectedBuyerGroupModeLabel}`;
  }

  get areAvailabilityFieldsDisabled() {
    return !this.draftBuyerGroupAccessEnabled;
  }

  get isAvailabilitySourceDisabled() {
    return !this.draftUsesPairedSource;
  }

  get draftBuyerGroupAccessEnabled() {
    return isBuyerGroupAccessEnabled(this.draft.buyerGroupAvailabilityMode);
  }

  get draftUsesPairedSource() {
    return usesPairedSource(this.draft.buyerGroupAvailabilityMode);
  }

  get draftUsesEmbeddedAccess() {
    return usesEmbeddedAccess(this.draft.buyerGroupAvailabilityMode);
  }

  get isSingularWebStoreRequired() {
    return false;
  }

  get singularWebStoreLabel() {
    const mode = resolveBuyerGroupAvailabilityMode(
      this.draft.buyerGroupAvailabilityMode
    );

    if (mode === BUYER_GROUP_MODE_PAIRED) {
      return "Legacy Web Store Fallback";
    }
    if (mode === BUYER_GROUP_MODE_EMBEDDED) {
      return "Web Store (legacy fallback)";
    }
    return "Web Store";
  }

  get singularWebStoreHelp() {
    const mode = resolveBuyerGroupAvailabilityMode(
      this.draft.buyerGroupAvailabilityMode
    );

    if (mode === BUYER_GROUP_MODE_PAIRED) {
      return "Optional backward-compatible fallback. It is used only when Shared Catalog Web Stores is empty; otherwise the plural store selection takes precedence.";
    }
    if (mode === BUYER_GROUP_MODE_EMBEDDED) {
      return "Optional backward-compatible fallback. Embedded access now resolves Buyer Groups from Shared Catalog Web Stores. Use this field only when the plural selection is empty.";
    }
    return "Select a Buyer Group Availability Mode to configure its Web Store scope.";
  }

  get draftBuyerGroupStoreGuidance() {
    const mode = resolveBuyerGroupAvailabilityMode(
      this.draft.buyerGroupAvailabilityMode
    );

    if (mode === BUYER_GROUP_MODE_PAIRED) {
      return "Paired Source prefers Shared Catalog Web Stores and unions Buyer Groups across them. Use the singular field only for an existing legacy configuration.";
    }
    if (mode === BUYER_GROUP_MODE_EMBEDDED) {
      return "Embedded access unions Buyer Groups across Shared Catalog Web Stores. The singular Web Store field is a backward-compatible fallback when no shared stores are selected.";
    }
    return "Web Store selections are not required while Buyer Group access is disabled.";
  }

  get selectedBuyerGroupModeLabel() {
    return formatBuyerGroupAvailabilityMode(
      this.draft.buyerGroupAvailabilityMode
    );
  }

  get selectedSyncModeLabel() {
    return resolveSyncMode(this.draft.syncMode);
  }

  get isDeltaDraft() {
    return this.selectedSyncModeLabel === SYNC_MODE_DELTA;
  }

  get selectedCatalogLabel() {
    return (
      this.getOptionLabel(this.catalogOptions, this.draft.catalogId) ||
      "All active products"
    );
  }

  get selectedWebStoreLabel() {
    return (
      this.getOptionLabel(this.webStoreOptions, this.draft.webStoreId) ||
      "Not selected"
    );
  }

  get selectedBuilderTypeLabel() {
    return (
      this.getOptionLabel(this.builderTypeOptions, this.draft.builderType) ||
      "Global default"
    );
  }

  get draftSummaryBaselineText() {
    if (!this.isDeltaDraft) {
      return "Self (full sync establishes the baseline)";
    }

    return this.draft.baselineFullConfigDeveloperName || "(Required)";
  }

  get existingConfigLabelMatch() {
    if (!this.draft.label || !this.catalogConfigs) {
      return false;
    }

    const normalizedLabel = this.draft.label.trim().toLowerCase();
    return this.catalogConfigs.some(
      (config) => (config.label || "").trim().toLowerCase() === normalizedLabel
    );
  }

  get existingDeveloperNameMatch() {
    if (!this.draft.developerName || !this.catalogConfigs) {
      return false;
    }

    const normalizedName = this.draft.developerName.trim().toLowerCase();
    return this.catalogConfigs.some(
      (config) =>
        (config.developerName || "").trim().toLowerCase() === normalizedName
    );
  }

  get hasDraftInput() {
    return Boolean(
      this.draft.label ||
        this.draft.developerName ||
        this.draft.coveoOrgId ||
        this.draft.sourceId ||
        this.isDeltaDraft ||
        this.draft.baselineFullConfigDeveloperName ||
        this.draft.availabilitySourceId ||
        this.draft.catalogId ||
        this.draft.webStoreId ||
        (this.draft.webStoreIds || []).length > 0 ||
        (this.draft.pricebookIds || []).length > 0 ||
        this.draft.builderType ||
        this.draft.productFilter ||
        this.draftBuyerGroupAccessEnabled ||
        (this.draft.additionalProductFields || []).length > 0
    );
  }

  get draftPreviewValidationMessages() {
    return this.draftPreview.validationMessages || [];
  }

  get draftPreviewWarningMessages() {
    const warnings = [...(this.draftPreview.warningMessages || [])];
    if (this.existingConfigLabelMatch) {
      warnings.unshift(
        "This label already exists in your current catalog job configurations."
      );
    }
    if (this.existingDeveloperNameMatch) {
      warnings.unshift(
        "This Developer Name already exists in your current catalog job configurations."
      );
    }
    return warnings;
  }

  get hasDraftValidationMessages() {
    return this.draftPreviewValidationMessages.length > 0;
  }

  get hasDraftWarningMessages() {
    return this.draftPreviewWarningMessages.length > 0;
  }

  get draftStatusLabel() {
    if (!this.hasDraftInput) {
      return "Start a draft";
    }
    if (this.hasDraftValidationMessages) {
      return "Needs attention";
    }
    if (this.hasDraftWarningMessages) {
      return "Ready with notes";
    }
    return "Ready to create";
  }

  get draftStatusClass() {
    if (!this.hasDraftInput) {
      return "draft-status draft-status--idle";
    }
    if (this.hasDraftValidationMessages) {
      return "draft-status draft-status--error";
    }
    if (this.hasDraftWarningMessages) {
      return "draft-status draft-status--warning";
    }
    return "draft-status draft-status--success";
  }

  get draftEstimatedProductCount() {
    return this.formatCount(this.draftPreview.estimatedProductCount);
  }

  get draftBuyerGroupCount() {
    if (!this.draftBuyerGroupAccessEnabled) {
      return "Disabled";
    }
    return this.formatCount(this.draftPreview.buyerGroupCount);
  }

  get draftSelectedFieldCount() {
    return this.formatCount(
      this.draftPreview.selectedFieldCount ||
        (this.draft.additionalProductFields || []).length
    );
  }

  get generatedConfigDraft() {
    const lines = [
      `DeveloperName: ${this.draft.developerName || "(Required)"}`,
      `MasterLabel: ${this.draft.label || "(Required)"}`,
      `CoveoOrgId__c: ${this.draft.coveoOrgId || "(Required)"}`,
      `SourceId__c: ${this.draft.sourceId || "(Required)"}`,
      `SyncMode__c: ${this.selectedSyncModeLabel}`,
      `BaselineFullConfigDeveloperName__c: ${
        this.isDeltaDraft
          ? this.draft.baselineFullConfigDeveloperName || "(Required)"
          : ""
      }`,
      `Locale__c: ${this.draft.locale || "(Required)"}`,
      `CatalogId__c: ${this.draft.catalogId || ""}`,
      `PricebookIds__c: ${(this.draft.pricebookIds || []).join(",")}`,
      `WebStoreIds__c: ${(this.draft.webStoreIds || []).join(",")}`,
      `BuilderType__c: ${this.draft.builderType || ""}`,
      `ProductFilter__c: ${this.draft.productFilter || ""}`,
      `AdditionalProductFields__c: ${(
        this.draft.additionalProductFields || []
      ).join(",")}`,
      `AvailabilitySourceId__c: ${this.draft.availabilitySourceId || ""}`,
      `BuyerGroupAvailabilityMode__c: ${
        this.draft.buyerGroupAvailabilityMode || BUYER_GROUP_MODE_DISABLED
      }`,
      `WebStoreId__c: ${this.draft.webStoreId || ""}`,
      `EnableBuyerGroupAvailability__c: ${this.draftBuyerGroupAccessEnabled}`,
      "IsActive__c: true"
    ];

    return lines.join("\n");
  }

  get isDraftReadyToCopy() {
    return this.hasDraftInput;
  }

  get isCopyDraftDisabled() {
    return !this.isDraftReadyToCopy;
  }

  get isResetDraftDisabled() {
    return !this.hasDraftInput;
  }

  get builderBadgeLabel() {
    return this.isDefaultBuilder ? "Default" : "Custom";
  }

  get builderBadgeClass() {
    return this.isDefaultBuilder ? "slds-theme_success" : "slds-theme_warning";
  }

  get draftSummaryCatalogText() {
    return this.selectedCatalogLabel;
  }

  get draftSummaryWebStoreText() {
    if (!this.draftBuyerGroupAccessEnabled) {
      return "Not required";
    }

    const mode = resolveBuyerGroupAvailabilityMode(
      this.draft.buyerGroupAvailabilityMode
    );
    const sharedStores = this.draft.webStoreIds || [];
    const sharedStoreText = `${sharedStores.length} shared store${
      sharedStores.length === 1 ? "" : "s"
    }`;

    if (mode === BUYER_GROUP_MODE_PAIRED) {
      if (sharedStores.length) {
        return `${sharedStoreText} (paired union)`;
      }
      return this.draft.webStoreId
        ? `${this.selectedWebStoreLabel} (legacy fallback)`
        : "Select shared stores or a legacy fallback";
    }

    if (mode === BUYER_GROUP_MODE_EMBEDDED) {
      if (sharedStores.length) {
        return `${sharedStoreText} (embedded union)`;
      }
      return this.draft.webStoreId
        ? `${this.selectedWebStoreLabel} (legacy fallback)`
        : "Select shared stores or a legacy fallback";
    }

    return "Not required";
  }

  get selectedConfigTitle() {
    return this.selectedConfigRow?.label || "Select a Catalog Job";
  }

  get selectedConfigSubtitle() {
    if (!this.selectedConfigRow) {
      return "Choose a catalog job from the list to inspect its configuration.";
    }

    return this.selectedConfigRow.jobSummary;
  }

  get selectedConfigOverviewFields() {
    if (!this.selectedConfigRow) {
      return [];
    }

    const selectedConfig = this.selectedConfigRow;
    const lastSyncValue = this.formatOptionalTimestamp(
      selectedConfig.lastSuccessfulSyncAt,
      "Never"
    );
    const lastFullSyncValue = this.formatOptionalTimestamp(
      selectedConfig.lastSuccessfulFullSyncAt,
      "Never"
    );

    return [
      {
        key: "syncType",
        label: "Sync Type",
        value: selectedConfig.syncMode || SYNC_MODE_FULL,
        helper:
          selectedConfig.syncMode === SYNC_MODE_DELTA
            ? selectedConfig.deltaReady
              ? "Trusted baseline available."
              : selectedConfig.deltaReadinessMessage
            : "Establishes the trusted export baseline."
      },
      {
        key: "schedule",
        label: "Schedule",
        value: this.selectedConfigScheduleCadence,
        helper: this.selectedConfigScheduleState
      },
      {
        key: "lastSync",
        label: "Latest Successful Sync",
        value: lastSyncValue,
        helper: `Last successful full baseline: ${lastFullSyncValue}`
      },
      {
        key: "accessMode",
        label: "Buyer Group Access",
        value: selectedConfig.buyerGroupAvailabilityModeLabel || "Disabled",
        helper: selectedConfig.destinationSummary || "No destination summary"
      }
    ];
  }

  get configSummaryFields() {
    if (!this.selectedConfigRow) {
      return [];
    }

    return [
      { label: "Label", value: this.selectedConfigRow.label || "(None)" },
      {
        label: "Developer Name",
        value: this.selectedConfigRow.developerName || "(None)"
      },
      { label: "Locale", value: this.selectedConfigRow.locale || "(None)" },
      {
        label: "Coveo Org Id",
        value: this.selectedConfigRow.coveoOrgId || "(None)"
      },
      {
        label: "Status",
        value: this.selectedConfigRow.statusSummary || "(None)"
      },
      {
        label: "Sync Type",
        value: this.selectedConfigRow.syncMode || SYNC_MODE_FULL
      },
      {
        label: "Resolved Builder",
        value: this.selectedConfigRow.builderSummary || "(None)"
      }
    ];
  }

  get configProductScopeFields() {
    if (!this.selectedConfigRow) {
      return [];
    }

    return [
      {
        label: "Catalog",
        value: this.selectedConfigRow.catalogDisplay || "All active products"
      },
      {
        label: "Product Source Id",
        value: this.selectedConfigRow.sourceId || "(None)"
      },
      {
        label: "Pricebooks",
        value:
          this.selectedConfigRow.pricebookDisplay || "All active pricebooks"
      },
      {
        label: "Shared Web Stores",
        value: this.selectedConfigRow.webStoreIdsDisplay || "Not configured"
      },
      {
        label: "Scope Summary",
        value: this.selectedConfigRow.scopeSummary || "No scope summary"
      },
      {
        label: "Product Filter",
        value: this.selectedConfigRow.productFilter || "No product filter"
      },
      {
        label: "Extra Fields",
        value:
          this.selectedConfigRow.additionalFieldSummary || "No extra fields"
      }
    ];
  }

  get configAvailabilityFields() {
    if (!this.selectedConfigRow) {
      return [];
    }

    return [
      {
        label: "Buyer Group Access Mode",
        value:
          this.selectedConfigRow.buyerGroupAvailabilityModeLabel || "Disabled"
      },
      {
        label: "Web Store",
        value: this.selectedConfigRow.webStoreDisplay || "Not required"
      },
      {
        label: "Multi-store Scope",
        value: this.selectedConfigRow.webStoreIdsDisplay || "Not configured"
      },
      {
        label: "Availability Source Id",
        value: this.selectedConfigRow.usesPairedSource
          ? this.selectedConfigRow.availabilitySourceId || "(None)"
          : "Not required"
      },
      {
        label: "Destination Summary",
        value: this.selectedConfigRow.destinationSummary || "(None)"
      }
    ];
  }

  get configAdvancedFields() {
    if (!this.selectedConfigRow) {
      return [];
    }

    return [
      {
        label: "Buyer Group Availability Mode",
        value:
          this.selectedConfigRow.buyerGroupAvailabilityMode ||
          BUYER_GROUP_MODE_DISABLED
      },
      {
        label: "Builder Type Value",
        value: this.selectedConfigRow.builderType || "(Global Default)"
      },
      {
        label: "Catalog Id",
        value: this.selectedConfigRow.catalogId || "(None)"
      },
      {
        label: "Web Store Id",
        value: this.selectedConfigRow.buyerGroupAvailabilityEnabled
          ? this.selectedConfigRow.webStoreId || "(None)"
          : "Not required"
      },
      {
        label: "Availability Source Id",
        value: this.selectedConfigRow.usesPairedSource
          ? this.selectedConfigRow.availabilitySourceId || "(None)"
          : "Not required"
      }
    ];
  }

  get configAdditionalFieldPills() {
    if (!this.selectedConfigRow?.additionalFieldList?.length) {
      return [];
    }

    return this.selectedConfigRow.additionalFieldList.map((fieldName) => ({
      label: fieldName,
      key: fieldName
    }));
  }

  get hasConfigAdditionalFieldPills() {
    return this.configAdditionalFieldPills.length > 0;
  }

  get configMetadataSummary() {
    return this.selectedConfigRow?.metadataSummary || "";
  }

  get configStatusBadgeLabel() {
    if (!this.selectedConfigRow) {
      return "Details";
    }

    return this.selectedConfigRow.isActive ? "Active" : "Inactive";
  }

  get configStatusBadgeClass() {
    return this.selectedConfigRow?.isActive
      ? "slds-theme_success"
      : "slds-theme_warning";
  }

  get configAvailabilityBadgeLabel() {
    if (!this.selectedConfigRow) {
      return "Buyer Group Access";
    }

    return this.selectedConfigRow.buyerGroupAvailabilityModeLabel;
  }

  get configAvailabilityBadgeClass() {
    return this.selectedConfigRow?.buyerGroupAvailabilityEnabled
      ? "slds-theme_success"
      : "slds-theme_default";
  }

  get hasSelectedConfigSchedule() {
    return this.selectedConfigRow?.isScheduled === true;
  }

  get selectedConfigScheduleCadence() {
    return this.selectedConfigRow?.scheduleCadenceSummary || "Not scheduled";
  }

  get selectedConfigScheduleState() {
    return this.selectedConfigRow?.scheduleStateLabel || "Not scheduled";
  }

  get selectedConfigScheduleNextRun() {
    return this.formatOptionalTimestamp(
      this.selectedConfigRow?.scheduleNextFireTime,
      "Not scheduled"
    );
  }

  get selectedConfigScheduleLastRun() {
    return this.formatOptionalTimestamp(
      this.selectedConfigRow?.schedulePreviousFireTime,
      "Never"
    );
  }

  get selectedConfigScheduledJobName() {
    return this.selectedConfigRow?.scheduledJobName || "Not scheduled";
  }

  get selectedConfigScheduleCronExpression() {
    return this.selectedConfigRow?.scheduleCronExpression || "Not scheduled";
  }

  get selectedScheduleCadenceType() {
    return (
      this.scheduleDraft?.cadenceType ||
      getDefaultScheduleCadenceType(this.selectedConfigRow?.syncMode)
    );
  }

  get isScheduleDraftHourly() {
    return this.selectedScheduleCadenceType === SCHEDULE_CADENCE_HOURLY;
  }

  get isScheduleDraftMinutes() {
    return this.selectedScheduleCadenceType === SCHEDULE_CADENCE_MINUTES;
  }

  get isScheduleDraftWeekly() {
    return this.selectedScheduleCadenceType === SCHEDULE_CADENCE_WEEKLY;
  }

  get scheduleIntervalMinutesValue() {
    return this.scheduleDraft?.intervalMinutes || "15";
  }

  get scheduleIntervalHoursValue() {
    return this.scheduleDraft?.intervalHours || "1";
  }

  get scheduleDayOfWeekValue() {
    return this.scheduleDraft?.dayOfWeek || "SUN";
  }

  get scheduleHourOfDayValue() {
    return this.scheduleDraft?.hourOfDay || "2";
  }

  get scheduleMinuteOfHourValue() {
    return this.scheduleDraft?.minuteOfHour || "0";
  }

  get scheduleMinuteLabel() {
    return this.isScheduleDraftMinutes
      ? "Starting Minute (0-59)"
      : "Minute (0-59)";
  }

  get scheduleSaveButtonLabel() {
    return this.isSavingSchedule ? "Saving..." : "Save Schedule";
  }

  get isScheduleSaveDisabled() {
    return (
      !this.selectedConfigRow ||
      this.isSavingSchedule ||
      this.isClearingSchedule
    );
  }

  get isScheduleClearDisabled() {
    return (
      !this.selectedConfigRow ||
      !this.hasSelectedConfigSchedule ||
      this.isSavingSchedule ||
      this.isClearingSchedule
    );
  }

  get isScheduleResetDisabled() {
    return (
      !this.selectedConfigRow ||
      this.isSavingSchedule ||
      this.isClearingSchedule
    );
  }

  get showCustomScheduleNotice() {
    return (
      this.hasSelectedConfigSchedule &&
      this.selectedConfigRow?.scheduleCadenceRecognized === false
    );
  }

  get showDeltaScheduleNotice() {
    return (
      this.selectedConfigRow?.syncMode === SYNC_MODE_DELTA &&
      this.selectedConfigRow?.deltaReady === false
    );
  }

  get hasRelatedScheduleConfigs() {
    return this.relatedScheduleConfigs.length > 0;
  }

  get relatedScheduleConfigs() {
    if (!this.selectedConfigRow || !this.catalogConfigs?.length) {
      return [];
    }

    const selectedConfig = this.selectedConfigRow;
    const relatedConfigs =
      selectedConfig.syncMode === SYNC_MODE_DELTA
        ? this.catalogConfigs.filter(
            (config) =>
              config.developerName ===
              selectedConfig.baselineFullConfigDeveloperName
          )
        : this.catalogConfigs.filter(
            (config) =>
              config.syncMode === SYNC_MODE_DELTA &&
              config.baselineFullConfigDeveloperName ===
                selectedConfig.developerName
          );

    return relatedConfigs
      .filter((config) => config.id !== selectedConfig.id)
      .map((config) => ({
        id: config.id,
        title: `${config.label} • ${config.syncMode}`,
        meta: [
          config.scheduleCadenceSummary || "Not scheduled",
          config.scheduleStateLabel || "Not scheduled"
        ].join(" • ")
      }));
  }

  handleDetailSectionToggle(event) {
    const openSections = event.detail?.openSections;
    if (Array.isArray(openSections)) {
      this.detailAccordionOpenSections = [...openSections];
      return;
    }

    this.detailAccordionOpenSections = openSections ? [openSections] : [];
  }

  handleTestConnection() {
    this.isTestingConnection = true;
    this.connectionTestResult = null;

    testNamedCredentialConnection()
      .then((result) => {
        this.connectionTestResult = result;
        if (result.success) {
          this.showToast("Success", result.message, "success");
        } else {
          this.showToast("Connection Issue", result.message, "warning");
        }
      })
      .catch((error) => {
        const message = this.reduceError(error);
        this.connectionTestResult = { success: false, message };
        this.showToast("Error", message, "error");
      })
      .finally(() => {
        this.isTestingConnection = false;
      });
  }

  handleOpenNamedCredentials() {
    this.navigateToSetupPage(this.namedCredentialSetupUrl);
  }

  handleOpenCustomMetadata() {
    this.navigateToSetupPage(this.customMetadataSetupUrl);
  }

  handleCustomBuilderInputChange(event) {
    this.customBuilderInput = event.target.value;
    this.builderValidationResult = null;
  }

  handleValidateBuilder() {
    if (!this.customBuilderInput) {
      this.showToast("Error", "Please enter a class name", "error");
      return;
    }

    this.isValidatingBuilder = true;
    this.builderValidationResult = null;

    validateBuilderClass({ className: this.customBuilderInput })
      .then((result) => {
        this.builderValidationResult = result;
        if (result.isValid) {
          this.showToast("Success", result.message, "success");
        } else {
          this.showToast("Validation Failed", result.message, "warning");
        }
      })
      .catch((error) => {
        const message = this.reduceError(error);
        this.builderValidationResult = { isValid: false, message };
        this.showToast("Error", message, "error");
      })
      .finally(() => {
        this.isValidatingBuilder = false;
      });
  }

  handleOpenJobConsole() {
    this[NavigationMixin.Navigate]({
      type: "standard__navItemPage",
      attributes: {
        apiName: "Catalog_Job_Console"
      }
    });
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

  handleWorkspaceSelect(event) {
    const workspace = event.currentTarget?.dataset?.workspace;
    if (!workspace || workspace === this.activeWorkspace) {
      return;
    }
    this.activeWorkspace = workspace;
  }

  handleSelectConfig(event) {
    const configId = event.currentTarget?.dataset?.configId;
    if (!configId) {
      return;
    }
    this.setSelectedConfig(configId);
  }

  handleLoadDraftClick(event) {
    const configId = event.currentTarget?.dataset?.configId;
    if (!configId) {
      return;
    }

    const match = (this.catalogConfigs || []).find(
      (config) => config.id === configId
    );
    if (match) {
      this.loadDraftFromConfig(match);
    }
  }

  handleScheduleDraftChange(event) {
    const fieldName = event.target.dataset.field;
    if (!fieldName) {
      return;
    }

    this.scheduleDraft = {
      ...this.buildScheduleDraftFromConfig(this.selectedConfigRow),
      ...this.scheduleDraft,
      [fieldName]: event.detail?.value ?? event.target.value ?? ""
    };
  }

  handleResetScheduleDraft() {
    this.initializeScheduleDraft(this.selectedConfigRow, true);
  }

  async handleSaveSchedule() {
    if (!this.selectedConfigRow) {
      return;
    }

    const validationMessage = this.validateScheduleDraft();
    if (validationMessage) {
      this.showToast("Schedule needs attention", validationMessage, "warning");
      return;
    }

    this.isSavingSchedule = true;

    try {
      await saveCatalogJobSchedule({
        jobConfigDeveloperName: this.selectedConfigRow.developerName,
        cadenceType: this.selectedScheduleCadenceType,
        intervalMinutes: this.parseInteger(this.scheduleDraft?.intervalMinutes),
        intervalHours: this.parseInteger(this.scheduleDraft?.intervalHours),
        dayOfWeek: this.scheduleDraft?.dayOfWeek,
        hourOfDay: this.parseInteger(this.scheduleDraft?.hourOfDay),
        minuteOfHour: this.parseInteger(this.scheduleDraft?.minuteOfHour)
      });
      await this.refreshCatalogJobConfigs();
      this.initializeScheduleDraft(this.selectedConfigRow, true);
      this.showToast(
        "Schedule saved",
        `Updated the native Salesforce schedule for ${this.selectedConfigRow.label}.`,
        "success"
      );
    } catch (error) {
      this.showToast(
        "Unable to save schedule",
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isSavingSchedule = false;
    }
  }

  async handleClearSchedule() {
    if (!this.selectedConfigRow) {
      return;
    }

    this.isClearingSchedule = true;

    try {
      await clearCatalogJobSchedule({
        jobConfigDeveloperName: this.selectedConfigRow.developerName
      });
      await this.refreshCatalogJobConfigs();
      this.initializeScheduleDraft(this.selectedConfigRow, true);
      this.showToast(
        "Schedule removed",
        `Removed the native Salesforce schedule for ${this.selectedConfigRow.label}.`,
        "success"
      );
    } catch (error) {
      this.showToast(
        "Unable to remove schedule",
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isClearingSchedule = false;
    }
  }

  handleChainDraftChange(event) {
    const fieldName = event.target.dataset.field;
    if (!fieldName) {
      return;
    }
    this.chainDraft = {
      ...this.chainDraft,
      [fieldName]:
        event.target.type === "checkbox" || event.target.type === "toggle"
          ? event.target.checked
          : (event.detail?.value ?? event.target.value ?? "")
    };
  }

  handleChainConfigsChange(event) {
    this.chainDraft = {
      ...this.chainDraft,
      configDeveloperNames: event.detail.value || []
    };
  }

  async handleSaveChainSchedule() {
    const validationMessage = this.validateScheduleDraft();
    if (validationMessage) {
      this.showToast("Schedule needs attention", validationMessage, "warning");
      return;
    }
    if (this.isChainScheduleSaveDisabled) {
      return;
    }

    this.isSavingChainSchedule = true;
    try {
      const result = await saveCatalogChainSchedule({
        chainName: this.chainNameValue,
        configDeveloperNames: this.chainConfigDeveloperNames,
        syncMode: this.selectedConfigRow.syncMode,
        includeAvailability: this.chainIncludeAvailability,
        cadenceType: this.selectedScheduleCadenceType,
        intervalMinutes: this.parseInteger(this.scheduleDraft?.intervalMinutes),
        intervalHours: this.parseInteger(this.scheduleDraft?.intervalHours),
        dayOfWeek: this.scheduleDraft?.dayOfWeek,
        hourOfDay: this.parseInteger(this.scheduleDraft?.hourOfDay),
        minuteOfHour: this.parseInteger(this.scheduleDraft?.minuteOfHour)
      });
      this.showToast(
        "Chain schedule saved",
        `${result.jobName} now covers ${this.chainConfigDeveloperNames.length} configs.`,
        "success"
      );
    } catch (error) {
      this.showToast(
        "Unable to save chain schedule",
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isSavingChainSchedule = false;
    }
  }

  async handleClearChainSchedule() {
    if (this.isChainScheduleClearDisabled || !this.selectedConfigRow) {
      return;
    }
    this.isClearingChainSchedule = true;
    try {
      await clearCatalogChainSchedule({
        chainName: this.chainNameValue,
        syncMode: this.selectedConfigRow.syncMode
      });
      this.showToast(
        "Chain schedule removed",
        `Removed ${this.chainNameValue}.`,
        "success"
      );
    } catch (error) {
      this.showToast(
        "Unable to remove chain schedule",
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isClearingChainSchedule = false;
    }
  }

  handleDraftInputChange(event) {
    const fieldName = event.target.dataset.field;
    if (!fieldName) {
      return;
    }

    const nextDraft = { ...this.draft };
    const previousGeneratedName = this.buildDeveloperName(this.draft.label);
    let value;

    if (event.target.type === "checkbox" || event.target.type === "toggle") {
      value = event.target.checked;
    } else {
      value = event.detail?.value ?? event.target.value ?? "";
    }

    nextDraft[fieldName] = value;

    if (fieldName === "label") {
      if (
        !this.draft.developerName ||
        this.draft.developerName === previousGeneratedName
      ) {
        nextDraft.developerName = this.buildDeveloperName(value);
      }
    }

    if (fieldName === "buyerGroupAvailabilityMode") {
      if (!isBuyerGroupAccessEnabled(value)) {
        nextDraft.webStoreId = "";
        nextDraft.availabilitySourceId = "";
      } else if (!usesPairedSource(value)) {
        nextDraft.availabilitySourceId = "";
      }
    }

    if (
      fieldName === "syncMode" &&
      resolveSyncMode(value) !== SYNC_MODE_DELTA
    ) {
      nextDraft.baselineFullConfigDeveloperName = "";
    }

    this.draft = nextDraft;
    this.schedulePreviewRefresh();
  }

  handleAdditionalFieldsChange(event) {
    this.draft = {
      ...this.draft,
      additionalProductFields: event.detail.value || []
    };
    this.schedulePreviewRefresh();
  }

  handlePricebookIdsChange(event) {
    this.draft = {
      ...this.draft,
      pricebookIds: event.detail.value || []
    };
    this.schedulePreviewRefresh();
  }

  handleWebStoreIdsChange(event) {
    this.draft = {
      ...this.draft,
      webStoreIds: event.detail.value || []
    };
    this.schedulePreviewRefresh();
  }

  handleResetDraft() {
    this.draft = { ...DEFAULT_DRAFT };
    this.draftPreview = { ...DEFAULT_PREVIEW };
    window.clearTimeout(this.previewRefreshTimeout);
  }

  async handleCopyDraft() {
    if (!this.isDraftReadyToCopy) {
      this.showToast(
        "Nothing to copy",
        "Start a draft before copying the config summary.",
        "warning"
      );
      return;
    }

    try {
      await navigator.clipboard.writeText(this.generatedConfigDraft);
      this.showToast(
        "Copied",
        "Catalog job draft copied to your clipboard.",
        "success"
      );
    } catch (error) {
      this.showToast(
        "Clipboard unavailable",
        "Copying to the clipboard is not available in this browser context.",
        "warning"
      );
    }
  }

  truncateText(text, maxLength) {
    if (!text) {
      return "";
    }
    if (text.length <= maxLength) {
      return text;
    }
    return text.substring(0, maxLength) + "...";
  }

  schedulePreviewRefresh() {
    window.clearTimeout(this.previewRefreshTimeout);

    if (!this.hasDraftInput) {
      this.draftPreview = { ...DEFAULT_PREVIEW };
      return;
    }

    this.previewRefreshTimeout = window.setTimeout(() => {
      this.refreshDraftPreview();
    }, PREVIEW_DEBOUNCE_MS);
  }

  refreshDraftPreview() {
    this.isLoadingDraftPreview = true;

    previewMultiStoreCatalogJobDraft({
      label: this.draft.label,
      developerName: this.draft.developerName,
      coveoOrgId: this.draft.coveoOrgId,
      sourceId: this.draft.sourceId,
      availabilitySourceId: this.draft.availabilitySourceId,
      syncMode: this.selectedSyncModeLabel,
      baselineFullConfigDeveloperName:
        this.draft.baselineFullConfigDeveloperName,
      catalogId: this.draft.catalogId,
      webStoreId: this.draft.webStoreId,
      webStoreIds: this.draft.webStoreIds,
      pricebookIds: this.draft.pricebookIds,
      locale: this.draft.locale,
      builderType: this.draft.builderType,
      buyerGroupAvailabilityMode: this.draft.buyerGroupAvailabilityMode,
      productFilter: this.draft.productFilter,
      additionalProductFields: this.draft.additionalProductFields
    })
      .then((result) => {
        this.draftPreview = {
          ...DEFAULT_PREVIEW,
          ...result
        };
      })
      .catch((error) => {
        const message = this.reduceError(error);
        this.draftPreview = {
          ...DEFAULT_PREVIEW,
          validationMessages: [message]
        };
      })
      .finally(() => {
        this.isLoadingDraftPreview = false;
      });
  }

  loadDraftFromConfig(config) {
    this.draft = {
      label: config.label || "",
      developerName: config.developerName || "",
      coveoOrgId: config.coveoOrgId || "",
      sourceId: config.sourceId || "",
      availabilitySourceId: config.availabilitySourceId || "",
      syncMode: resolveSyncMode(config.syncMode),
      baselineFullConfigDeveloperName:
        config.baselineFullConfigDeveloperName || "",
      locale: config.locale || "en-US",
      catalogId: config.catalogId || "",
      webStoreId: config.webStoreId || "",
      webStoreIds: this.parseAdditionalFields(config.webStoreIds),
      pricebookIds: this.parseAdditionalFields(config.pricebookIds),
      builderType:
        config.builderType && config.builderType !== "(Global Default)"
          ? config.builderType
          : "",
      buyerGroupAvailabilityMode: resolveBuyerGroupAvailabilityMode(
        config.buyerGroupAvailabilityMode,
        config.buyerGroupAvailabilityEnabled
      ),
      productFilter: config.productFilter || "",
      additionalProductFields: this.parseAdditionalFields(
        config.additionalProductFields
      )
    };

    this.schedulePreviewRefresh();
    this.showToast(
      "Draft loaded",
      `Loaded ${config.label} into the guided assistant.`,
      "success"
    );
  }

  parseAdditionalFields(value) {
    if (!value) {
      return [];
    }

    return value
      .split(",")
      .map((fieldName) => fieldName.trim())
      .filter(Boolean);
  }

  buildDeveloperName(label) {
    if (!label) {
      return "";
    }

    let generatedName = label
      .toUpperCase()
      .replace(/[^A-Z0-9]+/g, "_")
      .replace(/^_+|_+$/g, "")
      .replace(/_+/g, "_");

    if (!generatedName) {
      return "";
    }

    if (!/^[A-Z]/.test(generatedName)) {
      generatedName = `JOB_${generatedName}`;
    }

    return generatedName.substring(0, 40);
  }

  getOptionLabel(options, value) {
    if (!value || !options) {
      return "";
    }

    const match = options.find((option) => option.value === value);
    return match ? match.label : value;
  }

  formatCount(value) {
    return new Intl.NumberFormat().format(value || 0);
  }

  startCatalogConfigRefresh() {
    if (this.configRefreshTimerId) {
      return;
    }

    this.configRefreshTimerId = window.setInterval(() => {
      this.refreshCatalogJobConfigs();
    }, CONFIG_REFRESH_INTERVAL_MS);
  }

  stopCatalogConfigRefresh() {
    if (!this.configRefreshTimerId) {
      return;
    }

    window.clearInterval(this.configRefreshTimerId);
    this.configRefreshTimerId = null;
  }

  async refreshCatalogJobConfigs() {
    if (
      !this.wiredConfigsResult ||
      this.isRefreshingCatalogConfigs ||
      document.visibilityState === "hidden"
    ) {
      return;
    }

    this.isRefreshingCatalogConfigs = true;
    try {
      await refreshApex(this.wiredConfigsResult);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Error refreshing catalog job configurations:", error);
    } finally {
      this.isRefreshingCatalogConfigs = false;
    }
  }

  refreshCatalogConfigs() {
    const selectedConfigId = this.selectedConfigRow?.id;
    this.catalogConfigs = (this.rawCatalogConfigs || []).map((config) =>
      this.decorateConfig(config, selectedConfigId)
    );

    if (!this.catalogConfigs.length) {
      this.selectedConfigRow = null;
      this.scheduleDraft = null;
      this.scheduleDraftConfigId = null;
      return;
    }

    const nextSelectedConfig =
      this.catalogConfigs.find((config) => config.id === selectedConfigId) ||
      this.catalogConfigs[0];
    this.setSelectedConfig(nextSelectedConfig.id);
  }

  decorateConfig(config, selectedConfigId) {
    const additionalFieldList = this.parseAdditionalFields(
      config.additionalProductFields
    );
    const syncMode =
      config.syncMode === SYNC_MODE_DELTA ? SYNC_MODE_DELTA : SYNC_MODE_FULL;
    const deltaReady =
      syncMode === SYNC_MODE_DELTA ? config.deltaReady === true : true;
    const buyerGroupAvailabilityMode = resolveBuyerGroupAvailabilityMode(
      config.buyerGroupAvailabilityMode,
      config.buyerGroupAvailabilityEnabled
    );
    const buyerGroupAvailabilityEnabled = isBuyerGroupAccessEnabled(
      buyerGroupAvailabilityMode
    );
    const usesPaired = usesPairedSource(buyerGroupAvailabilityMode);
    const usesEmbedded = usesEmbeddedAccess(buyerGroupAvailabilityMode);
    const buyerGroupAvailabilityModeLabel = formatBuyerGroupAvailabilityMode(
      buyerGroupAvailabilityMode
    );
    const catalogLabel = config.catalogId
      ? this.getOptionLabel(this.catalogOptions, config.catalogId)
      : "";
    const webStoreLabel = config.webStoreId
      ? this.getOptionLabel(this.webStoreOptions, config.webStoreId)
      : "";
    const webStoreIdList = this.parseAdditionalFields(config.webStoreIds);
    const pricebookIdList = this.parseAdditionalFields(config.pricebookIds);
    const webStoreIdsDisplay = this.formatNamedIdList(
      this.webStoreOptions,
      webStoreIdList,
      "Not configured"
    );
    const pricebookDisplay = this.formatNamedIdList(
      this.pricebookOptions,
      pricebookIdList,
      "All active pricebooks"
    );
    const catalogDisplay = config.catalogId
      ? this.formatNamedValue(catalogLabel, config.catalogId)
      : "All active products";
    const webStoreDisplay = buyerGroupAvailabilityEnabled
      ? this.formatNamedValue(webStoreLabel, config.webStoreId, "Not selected")
      : "Not required";
    const builderSummary = this.getBuilderDisplayLabel(config.builderType);
    const experienceSummaryParts = [
      `Catalog: ${catalogLabel || config.catalogId || "All active products"}`,
      `Locale: ${config.locale || "(Missing)"}`
    ];
    const destinationSummaryParts = [
      `Org: ${config.coveoOrgId || "(Missing)"}`,
      `Products: ${config.sourceId || "(Missing)"}`
    ];
    const syncSummaryParts = [
      `Mode: ${syncMode}`,
      syncMode === SYNC_MODE_DELTA
        ? deltaReady
          ? "Delta ready"
          : config.deltaReadinessMessage || "Delta blocked"
        : "Seeds the trusted baseline",
      `Baseline: ${
        config.baselineFullConfigDeveloperName ||
        (syncMode === SYNC_MODE_DELTA ? "(Missing)" : "Self")
      }`
    ];
    const isScheduled = config.isScheduled === true;
    const scheduleCadenceSummary = this.describeScheduleCadence(config);
    const scheduleStateLabel = this.describeScheduleState(config);
    const inventoryExperienceSummaryParts = [
      catalogLabel || config.catalogId || "All active products",
      config.locale || "(Missing)"
    ];
    const inventorySupportParts = [
      buyerGroupAvailabilityEnabled
        ? `Access: ${buyerGroupAvailabilityModeLabel}`
        : "Access: Disabled",
      syncMode === SYNC_MODE_DELTA
        ? deltaReady
          ? "Delta ready"
          : config.deltaReadinessMessage || "Waiting for baseline"
        : "Trusted baseline",
      `Last sync: ${this.formatOptionalTimestamp(
        config.lastSuccessfulSyncAt,
        "Never"
      )}`
    ];

    if (buyerGroupAvailabilityEnabled) {
      inventoryExperienceSummaryParts.push(
        webStoreLabel || config.webStoreId || "(Missing)"
      );
    }

    if (buyerGroupAvailabilityEnabled) {
      experienceSummaryParts.push(
        `Store: ${webStoreLabel || config.webStoreId || "(Missing)"}`
      );
    } else {
      experienceSummaryParts.push("Store: Not required");
    }

    if (usesPaired) {
      destinationSummaryParts.push(
        `Availability: ${config.availabilitySourceId || "(Missing)"}`
      );
    }
    if (usesEmbedded) {
      destinationSummaryParts.push(
        `Access: ${config.sourceId || "(Missing)"} (embedded)`
      );
    }
    if (!buyerGroupAvailabilityEnabled) {
      destinationSummaryParts.push("Access: Disabled");
    }

    return {
      ...config,
      buyerGroupAvailabilityMode,
      buyerGroupAvailabilityModeLabel,
      buyerGroupAvailabilityEnabled,
      usesPairedSource: usesPaired,
      usesEmbeddedAccess: usesEmbedded,
      isSelected: config.id === selectedConfigId,
      cardClass: this.getConfigCardClass(config.id === selectedConfigId),
      activeStatusLabel: config.isActive ? "Active" : "Inactive",
      availabilityStatusLabel: buyerGroupAvailabilityEnabled
        ? buyerGroupAvailabilityModeLabel
        : "Access Disabled",
      activeStatusClass: config.isActive
        ? "detail-pill detail-pill--success"
        : "detail-pill detail-pill--neutral",
      availabilityStatusClass:
        syncMode === SYNC_MODE_DELTA
          ? deltaReady
            ? "detail-pill detail-pill--success"
            : "detail-pill detail-pill--warning"
          : "detail-pill detail-pill--neutral",
      availabilityStatusLabel:
        syncMode === SYNC_MODE_DELTA
          ? deltaReady
            ? "Delta Ready"
            : "Blocked"
          : "Baseline",
      syncStatusLabel: `${syncMode} Sync`,
      syncStatusClass:
        syncMode === SYNC_MODE_DELTA
          ? "detail-pill detail-pill--brand"
          : "detail-pill detail-pill--neutral",
      scheduleStatusLabel: isScheduled ? "Scheduled" : "Manual",
      scheduleStatusClass: isScheduled
        ? "detail-pill detail-pill--success"
        : "detail-pill detail-pill--neutral",
      inventoryRowClass:
        config.id === selectedConfigId
          ? "config-table__row config-table__row--selected"
          : "config-table__row",
      productFilter_truncated: this.truncateText(
        config.productFilter,
        TRUNCATE_LENGTH
      ),
      additionalProductFields_truncated: this.truncateText(
        config.additionalProductFields,
        TRUNCATE_LENGTH
      ),
      additionalFieldList,
      additionalFieldSummary: additionalFieldList.length
        ? `${additionalFieldList.length} field${additionalFieldList.length === 1 ? "" : "s"} selected`
        : "No extra fields",
      builderSummary,
      jobSummary: `${config.label}${
        config.developerName ? ` • ${config.developerName}` : ""
      }`,
      experienceSummary: experienceSummaryParts.join(" • "),
      destinationSummary: destinationSummaryParts.join(" • "),
      scopeSummary: config.productFilter
        ? `Filtered: ${this.truncateText(config.productFilter, 90)}`
        : "No product filter",
      statusSummary: [
        config.isActive ? "Active" : "Inactive",
        `Sync: ${syncMode}`,
        buyerGroupAvailabilityEnabled
          ? `Access: ${buyerGroupAvailabilityModeLabel}`
          : "Access disabled"
      ].join(" • "),
      syncMode,
      syncModeLabel: syncMode,
      deltaReady,
      deltaReadinessMessage:
        config.deltaReadinessMessage ||
        (syncMode === SYNC_MODE_DELTA
          ? "Run the baseline full sync once before delta sync."
          : "Full sync establishes the baseline."),
      baselineFullConfigDeveloperName:
        config.baselineFullConfigDeveloperName || "",
      syncSummary: syncSummaryParts.join(" • "),
      lastSuccessfulFullSyncAt: config.lastSuccessfulFullSyncAt || "",
      lastSuccessfulSyncAt: config.lastSuccessfulSyncAt || "",
      lastSyncSummary: [
        `Last full baseline: ${this.formatOptionalTimestamp(config.lastSuccessfulFullSyncAt, "Never")}`,
        `Latest successful sync: ${this.formatOptionalTimestamp(config.lastSuccessfulSyncAt, "Never")}`
      ].join(" • "),
      isScheduled,
      scheduledJobName: config.scheduledJobName || "",
      scheduleState: config.scheduleState || "",
      scheduleStateLabel,
      scheduleCronExpression: config.scheduleCronExpression || "",
      scheduleNextFireTime: config.scheduleNextFireTime || "",
      schedulePreviousFireTime: config.schedulePreviousFireTime || "",
      scheduleTimesTriggered: config.scheduleTimesTriggered || 0,
      scheduleCadenceRecognized: config.scheduleCadenceRecognized === true,
      scheduleCadenceType: config.scheduleCadenceType || "",
      scheduleIntervalMinutes:
        config.scheduleIntervalMinutes === null ||
        config.scheduleIntervalMinutes === undefined
          ? null
          : Number(config.scheduleIntervalMinutes),
      scheduleIntervalHours:
        config.scheduleIntervalHours === null ||
        config.scheduleIntervalHours === undefined
          ? null
          : Number(config.scheduleIntervalHours),
      scheduleDayOfWeek: config.scheduleDayOfWeek || "",
      scheduleHourOfDay:
        config.scheduleHourOfDay === null ||
        config.scheduleHourOfDay === undefined
          ? null
          : Number(config.scheduleHourOfDay),
      scheduleMinuteOfHour:
        config.scheduleMinuteOfHour === null ||
        config.scheduleMinuteOfHour === undefined
          ? null
          : Number(config.scheduleMinuteOfHour),
      scheduleCadenceSummary,
      scheduleSummary: isScheduled
        ? `${scheduleCadenceSummary} • Next ${this.formatOptionalTimestamp(
            config.scheduleNextFireTime,
            "Pending"
          )}`
        : "Not scheduled",
      inventoryExperienceSummary: inventoryExperienceSummaryParts.join(" • "),
      inventoryExperienceMeta: [
        `Locale: ${config.locale || "(Missing)"}`,
        buyerGroupAvailabilityEnabled
          ? `Store: ${webStoreLabel || config.webStoreId || "(Missing)"}`
          : "Store: Not required"
      ].join(" • "),
      inventoryRunSummary: isScheduled
        ? `${syncMode} • ${scheduleCadenceSummary}`
        : `${syncMode} • Manual launch`,
      inventoryRunMeta:
        syncMode === SYNC_MODE_DELTA
          ? deltaReady
            ? "Trusted baseline available"
            : config.deltaReadinessMessage || "Waiting for baseline"
          : "Trusted baseline export",
      inventoryTargetSummary: [
        `Products: ${config.sourceId || "(Missing)"}`,
        `Org: ${config.coveoOrgId || "(Missing)"}`
      ].join(" • "),
      inventoryScheduleSummary: isScheduled ? scheduleCadenceSummary : "Manual",
      inventoryScheduleMeta: isScheduled
        ? scheduleStateLabel
        : "Launch from the run console",
      inventorySourceSummary: config.sourceId || "(Missing)",
      inventorySourceMeta: config.coveoOrgId || "(Missing)",
      inventoryAccessSummary: buyerGroupAvailabilityModeLabel,
      inventoryAccessMeta: usesPaired
        ? `Availability: ${config.availabilitySourceId || "(Missing)"}`
        : usesEmbedded
          ? "Embedded in product source"
          : "No access export",
      inventoryLastSyncSummary: this.formatOptionalTimestamp(
        config.lastSuccessfulSyncAt,
        "Never"
      ),
      inventoryLastSyncMeta: `Last successful full baseline: ${this.formatOptionalTimestamp(
        config.lastSuccessfulFullSyncAt,
        "Never"
      )}`,
      inventorySupportSummary: inventorySupportParts.join(" • "),
      catalogLabel: catalogLabel || config.catalogId || "All active products",
      webStoreLabel: webStoreLabel || config.webStoreId || "Not selected",
      webStoreIdList,
      pricebookIdList,
      webStoreIdsDisplay,
      pricebookDisplay,
      catalogDisplay,
      webStoreDisplay,
      metadataSummary: this.buildConfigMetadataSummary({
        ...config,
        builderSummary,
        catalogDisplay,
        webStoreDisplay,
        additionalFieldList
      })
    };
  }

  getConfigCardClass(isSelected) {
    return isSelected ? "config-card config-card--selected" : "config-card";
  }

  setSelectedConfig(configId) {
    const previousSelectedConfigId = this.selectedConfigRow?.id;
    if (!configId || !this.catalogConfigs?.length) {
      this.selectedConfigRow = null;
      this.scheduleDraft = null;
      this.scheduleDraftConfigId = null;
      return;
    }

    let nextSelectedConfig = null;
    this.catalogConfigs = this.catalogConfigs.map((config) => {
      const isSelected = config.id === configId;
      const nextConfig = {
        ...config,
        isSelected,
        cardClass: this.getConfigCardClass(isSelected)
      };

      if (isSelected) {
        nextSelectedConfig = nextConfig;
      }

      return nextConfig;
    });

    this.selectedConfigRow = nextSelectedConfig;
    if (
      nextSelectedConfig &&
      previousSelectedConfigId !== nextSelectedConfig.id
    ) {
      this.chainDraft = {
        ...this.chainDraft,
        configDeveloperNames: [nextSelectedConfig.developerName]
      };
    }

    if (
      nextSelectedConfig &&
      (previousSelectedConfigId !== nextSelectedConfig.id ||
        !this.scheduleDraft ||
        this.scheduleDraftConfigId !== nextSelectedConfig.id)
    ) {
      this.initializeScheduleDraft(nextSelectedConfig, true);
    }
  }

  getBuilderDisplayLabel(builderTypeValue) {
    if (!builderTypeValue || builderTypeValue === "(Global Default)") {
      return `Global default (${this.builderClassName})`;
    }

    const mappedBuilderType = this.builderTypeOptions.find(
      (option) => option.value === builderTypeValue
    );
    if (mappedBuilderType) {
      return mappedBuilderType.label;
    }

    const mappedBuilderClass = (this.builderOptions || []).find(
      (option) => option.value === builderTypeValue
    );
    if (mappedBuilderClass) {
      return mappedBuilderClass.label;
    }

    return builderTypeValue;
  }

  getWorkspaceNavClass(workspaceName) {
    return this.activeWorkspace === workspaceName
      ? "workspace-nav__item workspace-nav__item--active"
      : "workspace-nav__item";
  }

  formatNamedValue(label, id, fallbackValue = "Not set") {
    if (!id) {
      return fallbackValue;
    }
    if (!label || label === id) {
      return id;
    }
    return `${label} (${id})`;
  }

  formatNamedIdList(options, ids, fallbackValue) {
    if (!ids?.length) {
      return fallbackValue;
    }
    return ids
      .map((id) => this.formatNamedValue(this.getOptionLabel(options, id), id))
      .join(", ");
  }

  buildConfigMetadataSummary(config) {
    return [
      `DeveloperName: ${config.developerName || ""}`,
      `MasterLabel: ${config.label || ""}`,
      `CoveoOrgId__c: ${config.coveoOrgId || ""}`,
      `SourceId__c: ${config.sourceId || ""}`,
      `AvailabilitySourceId__c: ${config.availabilitySourceId || ""}`,
      `BuyerGroupAvailabilityMode__c: ${
        config.buyerGroupAvailabilityMode || BUYER_GROUP_MODE_DISABLED
      }`,
      `CatalogId__c: ${config.catalogId || ""}`,
      `WebStoreId__c: ${config.webStoreId || ""}`,
      `WebStoreIds__c: ${config.webStoreIds || ""}`,
      `PricebookIds__c: ${config.pricebookIds || ""}`,
      `Locale__c: ${config.locale || ""}`,
      `BuilderType__c: ${
        config.builderType === "(Global Default)"
          ? ""
          : config.builderType || ""
      }`,
      `SyncMode__c: ${config.syncMode || SYNC_MODE_FULL}`,
      `BaselineFullConfigDeveloperName__c: ${
        config.baselineFullConfigDeveloperName || ""
      }`,
      `EnableBuyerGroupAvailability__c: ${Boolean(
        config.buyerGroupAvailabilityEnabled
      )}`,
      `ProductFilter__c: ${config.productFilter || ""}`,
      `AdditionalProductFields__c: ${(config.additionalFieldList || []).join(",")}`,
      `IsActive__c: ${Boolean(config.isActive)}`,
      `LastSuccessfulFullSyncAt: ${config.lastSuccessfulFullSyncAt || ""}`,
      `LastSuccessfulSyncAt: ${config.lastSuccessfulSyncAt || ""}`,
      `LastRunMode: ${config.lastRunMode || ""}`,
      `ScheduledJobName: ${config.scheduledJobName || ""}`,
      `ScheduleCronExpression: ${config.scheduleCronExpression || ""}`,
      `ScheduleState: ${config.scheduleState || ""}`
    ].join("\n");
  }

  buildScheduleDraftFromConfig(config) {
    const defaultCadenceType = getDefaultScheduleCadenceType(config?.syncMode);
    const recognizedCadenceType =
      config?.scheduleCadenceRecognized && config?.scheduleCadenceType
        ? config.scheduleCadenceType
        : defaultCadenceType;
    const defaultHourOfDay =
      resolveSyncMode(config?.syncMode) === SYNC_MODE_DELTA ? "0" : "2";

    return {
      cadenceType: recognizedCadenceType,
      intervalMinutes:
        config?.scheduleCadenceRecognized &&
        config?.scheduleCadenceType === SCHEDULE_CADENCE_MINUTES
          ? String(config.scheduleIntervalMinutes)
          : "15",
      intervalHours:
        config?.scheduleCadenceRecognized &&
        config?.scheduleCadenceType === SCHEDULE_CADENCE_HOURLY
          ? String(config.scheduleIntervalHours)
          : "1",
      dayOfWeek:
        config?.scheduleCadenceRecognized &&
        config?.scheduleCadenceType === SCHEDULE_CADENCE_WEEKLY &&
        config?.scheduleDayOfWeek
          ? config.scheduleDayOfWeek
          : "SUN",
      hourOfDay:
        config?.scheduleCadenceRecognized &&
        config?.scheduleCadenceType === SCHEDULE_CADENCE_WEEKLY &&
        config?.scheduleHourOfDay !== null &&
        config?.scheduleHourOfDay !== undefined
          ? String(config.scheduleHourOfDay)
          : defaultHourOfDay,
      minuteOfHour:
        config?.scheduleCadenceRecognized &&
        config?.scheduleMinuteOfHour !== null &&
        config?.scheduleMinuteOfHour !== undefined
          ? String(config.scheduleMinuteOfHour)
          : "0"
    };
  }

  initializeScheduleDraft(config, forceReset = false) {
    if (!config) {
      this.scheduleDraft = null;
      this.scheduleDraftConfigId = null;
      return;
    }

    if (
      !forceReset &&
      this.scheduleDraft &&
      this.scheduleDraftConfigId === config.id
    ) {
      return;
    }

    this.scheduleDraft = this.buildScheduleDraftFromConfig(config);
    this.scheduleDraftConfigId = config.id;
  }

  validateScheduleDraft() {
    const cadenceType = this.selectedScheduleCadenceType;
    const minuteOfHour = this.parseInteger(this.scheduleDraft?.minuteOfHour);

    if (minuteOfHour === null || minuteOfHour < 0 || minuteOfHour > 59) {
      return "Minute must be a whole number between 0 and 59.";
    }

    if (cadenceType === SCHEDULE_CADENCE_MINUTES) {
      const intervalMinutes = this.parseInteger(
        this.scheduleDraft?.intervalMinutes
      );
      if (
        intervalMinutes === null ||
        intervalMinutes < 1 ||
        intervalMinutes > 59
      ) {
        return "Minute schedules require an interval between 1 and 59 minutes.";
      }
      if (60 % intervalMinutes !== 0) {
        return "Minute schedules require an interval that evenly divides 60.";
      }
      if (60 / intervalMinutes > 4) {
        return "Minute schedules currently support up to four runs per hour.";
      }
      return "";
    }

    if (cadenceType === SCHEDULE_CADENCE_HOURLY) {
      const intervalHours = this.parseInteger(
        this.scheduleDraft?.intervalHours
      );
      if (intervalHours === null || intervalHours < 1 || intervalHours > 24) {
        return "Hourly schedules require an interval between 1 and 24 hours.";
      }
      return "";
    }

    if (cadenceType === SCHEDULE_CADENCE_WEEKLY) {
      const hourOfDay = this.parseInteger(this.scheduleDraft?.hourOfDay);
      if (hourOfDay === null || hourOfDay < 0 || hourOfDay > 23) {
        return "Weekly schedules require an hour between 0 and 23.";
      }
      if (!this.scheduleDraft?.dayOfWeek) {
        return "Weekly schedules require a day of week.";
      }
      return "";
    }

    return "Choose a supported schedule cadence.";
  }

  parseInteger(rawValue) {
    if (rawValue === null || rawValue === undefined || rawValue === "") {
      return null;
    }

    const parsedValue = Number.parseInt(rawValue, 10);
    return Number.isNaN(parsedValue) ? null : parsedValue;
  }

  describeScheduleState(config) {
    if (config.isScheduled !== true) {
      return "Not scheduled";
    }

    switch (config.scheduleState) {
      case "WAITING":
        return "Scheduled";
      case "ACQUIRED":
        return "Queued";
      case "EXECUTING":
        return "Running";
      case "PAUSED":
      case "PAUSED_BLOCKED":
        return "Paused";
      case "BLOCKED":
        return "Blocked";
      default:
        return config.scheduleState || "Scheduled";
    }
  }

  describeScheduleCadence(config) {
    if (config.isScheduled !== true) {
      return "Not scheduled";
    }

    if (config.scheduleCadenceRecognized !== true) {
      return config.scheduleCronExpression
        ? `Custom cron: ${config.scheduleCronExpression}`
        : "Scheduled";
    }

    if (config.scheduleCadenceType === SCHEDULE_CADENCE_HOURLY) {
      const intervalHours = Number(config.scheduleIntervalHours) || 1;
      const minuteOfHour = Number(config.scheduleMinuteOfHour) || 0;
      return `Every ${intervalHours} hour${
        intervalHours === 1 ? "" : "s"
      } at :${padNumber(minuteOfHour)}`;
    }

    if (config.scheduleCadenceType === SCHEDULE_CADENCE_MINUTES) {
      const intervalMinutes = Number(config.scheduleIntervalMinutes) || 15;
      const minuteOfHour = Number(config.scheduleMinuteOfHour) || 0;
      return minuteOfHour > 0
        ? `Every ${intervalMinutes} minute${
            intervalMinutes === 1 ? "" : "s"
          } starting at :${padNumber(minuteOfHour)}`
        : `Every ${intervalMinutes} minute${intervalMinutes === 1 ? "" : "s"}`;
    }

    if (config.scheduleCadenceType === SCHEDULE_CADENCE_WEEKLY) {
      const dayLabel =
        SCHEDULE_DAY_LABELS[config.scheduleDayOfWeek] || "Unknown day";
      const hourOfDay = Number(config.scheduleHourOfDay) || 0;
      const minuteOfHour = Number(config.scheduleMinuteOfHour) || 0;
      return `Every ${dayLabel} at ${padNumber(hourOfDay)}:${padNumber(
        minuteOfHour
      )}`;
    }

    return config.scheduleCronExpression || "Scheduled";
  }

  formatOptionalTimestamp(isoValue, fallbackValue) {
    if (!isoValue) {
      return fallbackValue;
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
    let message = "Unknown error";
    if (Array.isArray(error?.body)) {
      message = error.body.map((entry) => entry.message).join(", ");
    } else if (error?.body?.message) {
      message = error.body.message;
    }
    return message;
  }
}
