import { LightningElement, wire, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";

import getNamedCredentialStatus from "@salesforce/apex/CoveoCommerceSetupController.getNamedCredentialStatus";
import getCatalogJobConfigs from "@salesforce/apex/CoveoCommerceSetupController.getCatalogJobConfigs";
import getActiveBuilderMapping from "@salesforce/apex/CoveoCommerceSetupController.getActiveBuilderMapping";
import getBuilderClassOptions from "@salesforce/apex/CoveoCommerceSetupController.getBuilderClassOptions";
import getSetupWorkspaceOptions from "@salesforce/apex/CoveoCommerceSetupController.getSetupWorkspaceOptions";
import previewCatalogJobDraft from "@salesforce/apex/CoveoCommerceSetupController.previewCatalogJobDraft";
import testNamedCredentialConnection from "@salesforce/apex/CoveoCommerceSetupController.testNamedCredentialConnection";
import validateBuilderClass from "@salesforce/apex/CoveoCommerceSetupController.validateBuilderClass";

const TRUNCATE_LENGTH = 50;
const PREVIEW_DEBOUNCE_MS = 350;
const CONFIG_REFRESH_INTERVAL_MS = 15000;
const BUYER_GROUP_MODE_DISABLED = "Disabled";
const BUYER_GROUP_MODE_PAIRED = "PairedSource";
const BUYER_GROUP_MODE_EMBEDDED = "Embedded";
const BUYER_GROUP_MODE_DUAL = "DualWrite";
const SYNC_MODE_FULL = "Full";
const SYNC_MODE_DELTA = "Delta";
const SYNC_MODE_OPTIONS = Object.freeze([
  { label: "Full", value: SYNC_MODE_FULL },
  { label: "Delta", value: SYNC_MODE_DELTA }
]);
const BUYER_GROUP_MODE_OPTIONS = Object.freeze([
  { label: "Disabled", value: BUYER_GROUP_MODE_DISABLED },
  { label: "Paired Source", value: BUYER_GROUP_MODE_PAIRED },
  { label: "Embedded", value: BUYER_GROUP_MODE_EMBEDDED },
  { label: "Dual Write", value: BUYER_GROUP_MODE_DUAL }
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
  return (
    resolveBuyerGroupAvailabilityMode(mode) !== BUYER_GROUP_MODE_DISABLED
  );
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

function resolveSyncMode(mode) {
  return mode === SYNC_MODE_DELTA ? SYNC_MODE_DELTA : SYNC_MODE_FULL;
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
    productCatalogs: [],
    builderTypeOptions: [],
    productFieldOptions: []
  };
  @track isLoadingWorkspaceOptions = true;
  @track draft = { ...DEFAULT_DRAFT };
  @track draftPreview = { ...DEFAULT_PREVIEW };
  @track isLoadingDraftPreview = false;

  namedCredentialSetupUrl = "/lightning/setup/NamedCredential/home";
  customMetadataSetupUrl = "/lightning/setup/CustomMetadata/home";
  previewRefreshTimeout;
  configRefreshTimerId;
  wiredConfigsResult;
  isRefreshingCatalogConfigs = false;

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
        builderTypeOptions: data.builderTypeOptions || [],
        productFieldOptions: data.productFieldOptions || []
      };
      this.refreshCatalogConfigs();
    } else if (error) {
      this.workspaceOptions = {
        webStores: [],
        productCatalogs: [],
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

  get selectedBuyerGroupModeLabel() {
    return formatBuyerGroupAvailabilityMode(this.draft.buyerGroupAvailabilityMode);
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
        this.isDeltaDraft ? this.draft.baselineFullConfigDeveloperName || "(Required)" : ""
      }`,
      `Locale__c: ${this.draft.locale || "(Required)"}`,
      `CatalogId__c: ${this.draft.catalogId || ""}`,
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
    return this.selectedWebStoreLabel;
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
          this.selectedConfigRow.buyerGroupAvailabilityModeLabel ||
          "Disabled"
      },
      {
        label: "Web Store",
        value: this.selectedConfigRow.webStoreDisplay || "Not required"
      },
      {
        label: "Availability Source Id",
        value:
          this.selectedConfigRow.usesPairedSource
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
        value:
          this.selectedConfigRow.buyerGroupAvailabilityEnabled
            ? this.selectedConfigRow.webStoreId || "(None)"
            : "Not required"
      },
      {
        label: "Availability Source Id",
        value:
          this.selectedConfigRow.usesPairedSource
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
    window.open(this.namedCredentialSetupUrl, "_blank");
  }

  handleOpenCustomMetadata() {
    window.open(this.customMetadataSetupUrl, "_blank");
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

    if (fieldName === "syncMode" && resolveSyncMode(value) !== SYNC_MODE_DELTA) {
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

    previewCatalogJobDraft({
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
    const deltaReady = syncMode === SYNC_MODE_DELTA ? config.deltaReady === true : true;
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
        config.baselineFullConfigDeveloperName || (syncMode === SYNC_MODE_DELTA ? "(Missing)" : "Self")
      }`
    ];

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
      availabilityStatusClass: buyerGroupAvailabilityEnabled
        ? "detail-pill detail-pill--success"
        : "detail-pill detail-pill--neutral",
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
        `Last full: ${this.formatOptionalTimestamp(config.lastSuccessfulFullSyncAt, "Never")}`,
        `Last sync: ${this.formatOptionalTimestamp(config.lastSuccessfulSyncAt, "Never")}`
      ].join(" • "),
      catalogLabel: catalogLabel || config.catalogId || "All active products",
      webStoreLabel: webStoreLabel || config.webStoreId || "Not selected",
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
    if (!configId || !this.catalogConfigs?.length) {
      this.selectedConfigRow = null;
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
      `LastRunMode: ${config.lastRunMode || ""}`
    ].join("\n");
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
