import { LightningElement, wire, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

import listConfigs from "@salesforce/apex/CatalogJobRunner.listConfigs";
import runSingle from "@salesforce/apex/CatalogJobRunner.runSingle";
import runSingleAvailability from "@salesforce/apex/CatalogJobRunner.runSingleAvailability";
import runSingleBoth from "@salesforce/apex/CatalogJobRunner.runSingleBoth";
import runAllActive from "@salesforce/apex/CatalogJobRunner.runAllActive";
import runAllActiveAvailability from "@salesforce/apex/CatalogJobRunner.runAllActiveAvailability";
import runAllActiveBoth from "@salesforce/apex/CatalogJobRunner.runAllActiveBoth";

const TRUNCATE_LENGTH = 50;

const RUN_PRODUCTS_COL = {
  label: "Products",
  type: "button",
  initialWidth: 130,
  typeAttributes: {
    label: "Run Product",
    name: "runProduct",
    variant: "brand-outline",
    title: "Run the product export now"
  }
};

const RUN_AVAILABILITY_COL = {
  label: "Availability",
  type: "button",
  initialWidth: 130,
  typeAttributes: {
    label: "Run Avail",
    name: "runAvailability",
    variant: "neutral",
    title: "Run the Buyer Group availability export now"
  }
};

const RUN_BOTH_COL = {
  label: "Both",
  type: "button",
  initialWidth: 110,
  typeAttributes: {
    label: "Run Both",
    name: "runBoth",
    variant: "brand",
    title: "Run both the product and availability exports now"
  }
};

const VIEW_DETAILS_COL = {
  label: "Details",
  type: "button",
  initialWidth: 90,
  typeAttributes: {
    label: "View",
    name: "viewDetails",
    variant: "neutral",
    title: "View full field details"
  }
};

export default class CatalogJobConsole extends LightningElement {
  @track configs;
  @track error;
  @track showDetailsModal = false;
  @track selectedRow = null;

  columns = [
    RUN_PRODUCTS_COL,
    RUN_AVAILABILITY_COL,
    RUN_BOTH_COL,
    VIEW_DETAILS_COL,
    { label: "Label", fieldName: "Label", wrapText: true },
    { label: "Locale", fieldName: "Locale__c" },
    { label: "Catalog ID", fieldName: "CatalogId__c", wrapText: true },
    { label: "Builder Type", fieldName: "BuilderType__c", wrapText: true },
    { label: "Coveo Org Id", fieldName: "CoveoOrgId__c" },
    { label: "Product Source Id", fieldName: "SourceId__c" },
    {
      label: "Availability Source Id",
      fieldName: "AvailabilitySourceId__c",
      wrapText: true
    },
    { label: "Web Store Id", fieldName: "WebStoreId__c", wrapText: true },
    {
      label: "Active",
      fieldName: "IsActive__c",
      type: "boolean",
      cellAttributes: { alignment: "center" }
    },
    {
      label: "Availability Enabled",
      fieldName: "EnableBuyerGroupAvailability__c",
      type: "boolean",
      cellAttributes: { alignment: "center" }
    },
    {
      label: "Product Filter",
      fieldName: "ProductFilter__c_truncated",
      wrapText: false,
      cellAttributes: { class: "slds-truncate" }
    },
    {
      label: "Extra Fields",
      fieldName: "AdditionalProductFields__c_truncated",
      wrapText: false,
      cellAttributes: { class: "slds-truncate" }
    }
  ];

  @wire(listConfigs)
  wiredConfigs({ data, error }) {
    if (data) {
      // Add truncated versions of large text fields
      this.configs = data.map((config) => ({
        ...config,
        ProductFilter__c_truncated: this.truncateText(
          config.ProductFilter__c,
          TRUNCATE_LENGTH
        ),
        AdditionalProductFields__c_truncated: this.truncateText(
          config.AdditionalProductFields__c,
          TRUNCATE_LENGTH
        )
      }));
      this.error = undefined;
    } else if (error) {
      this.error = error;
      this.configs = undefined;
    }
  }

  truncateText(text, maxLength) {
    if (!text) return "";
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength) + "...";
  }

  get errorMessage() {
    if (!this.error) return "";
    if (Array.isArray(this.error.body)) {
      return this.error.body.map((e) => e.message).join(", ");
    }
    if (this.error.body && this.error.body.message) {
      return this.error.body.message;
    }
    return "Unknown error";
  }

  // Small stats for header
  get totalJobs() {
    return this.configs ? this.configs.length : 0;
  }

  get activeJobs() {
    return this.configs ? this.configs.filter((c) => c.IsActive__c).length : 0;
  }

  get inactiveJobs() {
    return this.configs ? this.configs.filter((c) => !c.IsActive__c).length : 0;
  }

  get isLoading() {
    return !this.configs && !this.error;
  }

  handleRunAll() {
    runAllActive()
      .then(() => {
        this.showToast("Success", "Started all active catalog jobs", "success");
      })
      .catch((err) => {
        const msg = this.reduceError(err);
        this.showToast("Error", msg, "error");
        // eslint-disable-next-line no-console
        console.error("runAllActive error", err);
      });
  }

  handleRunAllAvailability() {
    runAllActiveAvailability()
      .then(() => {
        this.showToast(
          "Success",
          "Started all active availability jobs",
          "success"
        );
      })
      .catch((err) => {
        const msg = this.reduceError(err);
        this.showToast("Error", msg, "error");
        // eslint-disable-next-line no-console
        console.error("runAllActiveAvailability error", err);
      });
  }

  handleRunAllBoth() {
    runAllActiveBoth()
      .then(() => {
        this.showToast(
          "Success",
          "Started all active product and availability jobs",
          "success"
        );
      })
      .catch((err) => {
        const msg = this.reduceError(err);
        this.showToast("Error", msg, "error");
        // eslint-disable-next-line no-console
        console.error("runAllActiveBoth error", err);
      });
  }

  handleRowAction(event) {
    const actionName = event.detail.action.name;
    const row = event.detail.row;
    // eslint-disable-next-line no-console
    console.log("Row action fired", actionName, row);

    if (actionName === "runProduct") {
      this.handleRunSingle(row.DeveloperName);
    } else if (actionName === "runAvailability") {
      this.handleRunSingleAvailability(row.DeveloperName);
    } else if (actionName === "runBoth") {
      this.handleRunSingleBoth(row.DeveloperName);
    } else if (actionName === "viewDetails") {
      this.selectedRow = row;
      this.showDetailsModal = true;
    }
  }

  handleCloseModal() {
    this.showDetailsModal = false;
    this.selectedRow = null;
  }

  get modalTitle() {
    return this.selectedRow ? `Details: ${this.selectedRow.Label}` : "Details";
  }

  get productFilter() {
    return this.selectedRow?.ProductFilter__c || "(None)";
  }

  get additionalFields() {
    return this.selectedRow?.AdditionalProductFields__c || "(None)";
  }

  get availabilitySourceId() {
    return this.selectedRow?.AvailabilitySourceId__c || "(None)";
  }

  get webStoreId() {
    return this.selectedRow?.WebStoreId__c || "(None)";
  }

  get availabilityEnabled() {
    return this.selectedRow?.EnableBuyerGroupAvailability__c
      ? "Enabled"
      : "Disabled";
  }

  handleRunSingle(devName) {
    runSingle({ jobConfigDeveloperName: devName })
      .then(() => {
        this.showToast(
          "Success",
          `Started product export job: ${devName}`,
          "success"
        );
      })
      .catch((err) => {
        const msg = this.reduceError(err);
        this.showToast("Error", msg, "error");
        // eslint-disable-next-line no-console
        console.error("runSingle error", err);
      });
  }

  handleRunSingleAvailability(devName) {
    runSingleAvailability({ jobConfigDeveloperName: devName })
      .then(() => {
        this.showToast(
          "Success",
          `Started availability export job: ${devName}`,
          "success"
        );
      })
      .catch((err) => {
        const msg = this.reduceError(err);
        this.showToast("Error", msg, "error");
        // eslint-disable-next-line no-console
        console.error("runSingleAvailability error", err);
      });
  }

  handleRunSingleBoth(devName) {
    runSingleBoth({ jobConfigDeveloperName: devName })
      .then(() => {
        this.showToast(
          "Success",
          `Started product and availability export jobs: ${devName}`,
          "success"
        );
      })
      .catch((err) => {
        const msg = this.reduceError(err);
        this.showToast("Error", msg, "error");
        // eslint-disable-next-line no-console
        console.error("runSingleBoth error", err);
      });
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

  reduceError(err) {
    let message = "Unknown error";
    if (Array.isArray(err?.body)) {
      message = err.body.map((e) => e.message).join(", ");
    } else if (err?.body?.message) {
      message = err.body.message;
    }
    return message;
  }
}
