import { LightningElement, wire, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

import getNamedCredentialStatus from "@salesforce/apex/CoveoCommerceSetupController.getNamedCredentialStatus";
import getCatalogJobConfigs from "@salesforce/apex/CoveoCommerceSetupController.getCatalogJobConfigs";
import getActiveBuilderMapping from "@salesforce/apex/CoveoCommerceSetupController.getActiveBuilderMapping";
import getBuilderClassOptions from "@salesforce/apex/CoveoCommerceSetupController.getBuilderClassOptions";
import testNamedCredentialConnection from "@salesforce/apex/CoveoCommerceSetupController.testNamedCredentialConnection";
import validateBuilderClass from "@salesforce/apex/CoveoCommerceSetupController.validateBuilderClass";

const CONFIG_COLUMNS = [
  { label: "Label", fieldName: "label", wrapText: true },
  { label: "Locale", fieldName: "locale" },
  { label: "Coveo Org Id", fieldName: "coveoOrgId" },
  { label: "Source Id", fieldName: "sourceId" },
  {
    label: "Active",
    fieldName: "isActive",
    type: "boolean",
    cellAttributes: { alignment: "center" }
  },
  { label: "Product Filter", fieldName: "productFilter", wrapText: true },
  {
    label: "Extra Fields",
    fieldName: "additionalProductFields",
    wrapText: true
  }
];

export default class CoveoCommerceSetup extends NavigationMixin(
  LightningElement
) {
  // Credential status
  @track credentialStatus = null;
  @track isLoadingCredential = true;
  @track isTestingConnection = false;
  @track connectionTestResult = null;

  // Catalog configs
  @track catalogConfigs = null;
  @track isLoadingConfigs = true;
  configColumns = CONFIG_COLUMNS;

  // Builder mapping
  @track builderMapping = null;
  @track builderOptions = null;
  @track isLoadingBuilder = true;
  @track customBuilderInput = "";
  @track isValidatingBuilder = false;
  @track builderValidationResult = null;

  // Setup URLs (static Lightning Setup paths)
  namedCredentialSetupUrl = "/lightning/setup/NamedCredential/home";
  customMetadataSetupUrl = "/lightning/setup/CustomMetadata/home";

  // Credential getters
  get credentialStatusLabel() {
    return this.credentialStatus?.status || "Unknown";
  }

  get credentialStatusClass() {
    if (this.credentialStatus?.exists) {
      return "slds-badge slds-theme_success";
    }
    // Show warning style for "API Key Missing" (partial configuration)
    if (this.credentialStatus?.status === "API Key Missing") {
      return "slds-badge slds-theme_warning";
    }
    return "slds-badge slds-theme_error";
  }

  get credentialEndpoint() {
    return this.credentialStatus?.endpoint || "Not configured";
  }

  // Connection test getters
  get connectionTestClass() {
    const base = "slds-m-top_small slds-p-around_x-small slds-border_left ";
    if (this.connectionTestResult?.success) {
      return base + "connection-success";
    }
    return base + "connection-error";
  }

  get connectionTestIcon() {
    if (this.connectionTestResult?.success) {
      return "utility:success";
    }
    return "utility:error";
  }

  get connectionTestMessage() {
    return this.connectionTestResult?.message || "";
  }

  // Config getters
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

  get activeConfigs() {
    return this.catalogConfigs
      ? this.catalogConfigs.filter((c) => c.isActive).length
      : 0;
  }

  get inactiveConfigs() {
    return this.catalogConfigs
      ? this.catalogConfigs.filter((c) => !c.isActive).length
      : 0;
  }

  // Builder getters
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
    if (this.builderValidationResult?.isValid) {
      return "utility:success";
    }
    return "utility:error";
  }

  get builderValidationMessage() {
    return this.builderValidationResult?.message || "";
  }

  // Wired data
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
  wiredConfigs({ data, error }) {
    this.isLoadingConfigs = false;
    if (data) {
      this.catalogConfigs = data;
    } else if (error) {
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
    } else if (error) {
      this.builderOptions = [];
      // eslint-disable-next-line no-console
      console.error("Error loading builder options:", error);
    }
  }

  // Event handlers
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

  // Utility methods
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
      message = error.body.map((e) => e.message).join(", ");
    } else if (error?.body?.message) {
      message = error.body.message;
    }
    return message;
  }
}
