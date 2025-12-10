import { LightningElement, wire, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

import listConfigs from "@salesforce/apex/CatalogJobRunner.listConfigs";
import runSingle from "@salesforce/apex/CatalogJobRunner.runSingle";
import runAllActive from "@salesforce/apex/CatalogJobRunner.runAllActive";

const ACTIONS_COL = {
  label: "Actions",
  type: "button",
  initialWidth: 110,
  typeAttributes: {
    label: "Run",
    name: "run",
    variant: "brand-outline",
    title: "Run this catalog job now"
  }
};

export default class CatalogJobConsole extends LightningElement {
  @track configs;
  @track error;

  columns = [
    ACTIONS_COL,
    { label: "Label", fieldName: "Label", wrapText: true },
    { label: "Locale", fieldName: "Locale__c" },
    { label: "Builder Type", fieldName: "BuilderType__c", wrapText: true },
    { label: "Coveo Org Id", fieldName: "CoveoOrgId__c" },
    { label: "Source Id", fieldName: "SourceId__c" },
    {
      label: "Active",
      fieldName: "IsActive__c",
      type: "boolean",
      cellAttributes: { alignment: "center" }
    },
    { label: "Product Filter", fieldName: "ProductFilter__c", wrapText: true },
    {
      label: "Extra Fields",
      fieldName: "AdditionalProductFields__c",
      wrapText: true
    }
  ];

  @wire(listConfigs)
  wiredConfigs({ data, error }) {
    if (data) {
      this.configs = data;
      this.error = undefined;
    } else if (error) {
      this.error = error;
      this.configs = undefined;
    }
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

  handleRowAction(event) {
    const actionName = event.detail.action.name;
    const row = event.detail.row;
    // eslint-disable-next-line no-console
    console.log("Row action fired", actionName, row);

    if (actionName === "run") {
      this.handleRunSingle(row.DeveloperName);
    }
  }

  handleRunSingle(devName) {
    runSingle({ jobConfigDeveloperName: devName })
      .then(() => {
        this.showToast("Success", `Started catalog job: ${devName}`, "success");
      })
      .catch((err) => {
        const msg = this.reduceError(err);
        this.showToast("Error", msg, "error");
        // eslint-disable-next-line no-console
        console.error("runSingle error", err);
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
