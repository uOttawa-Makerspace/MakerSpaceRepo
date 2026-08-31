import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "input",
    "clearButton",
    "activeRow",
    "inactiveRow",
    "activeCount",
    "inactiveCount",
    "activeEmpty",
    "inactiveEmpty",
    "activeTableContainer",
    "inactiveTableContainer",
  ];

  connect() {
    this.totalActive = this.activeRowTargets.length;
    this.totalInactive = this.inactiveRowTargets.length;
  }

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase();

    // Toggle clear button
    if (this.hasClearButtonTarget) {
      this.clearButtonTarget.classList.toggle("d-none", query.length === 0);
    }

    // Filter Active Volunteers
    let activeVisible = 0;
    this.activeRowTargets.forEach((row) => {
      const match =
        query === "" || row.textContent.toLowerCase().includes(query);
      row.classList.toggle("d-none", !match);
      if (match) activeVisible++;
    });

    if (this.hasActiveCountTarget) {
      this.activeCountTarget.textContent =
        query === "" ? this.totalActive : activeVisible;
    }

    if (this.hasActiveEmptyTarget && this.hasActiveTableContainerTarget) {
      const showEmpty = activeVisible === 0 && this.totalActive > 0;
      this.activeEmptyTarget.classList.toggle("d-none", !showEmpty);
      this.activeTableContainerTarget.classList.toggle("d-none", showEmpty);
    }

    // Filter Inactive Volunteers
    let inactiveVisible = 0;
    this.inactiveRowTargets.forEach((row) => {
      const match =
        query === "" || row.textContent.toLowerCase().includes(query);
      row.classList.toggle("d-none", !match);
      if (match) inactiveVisible++;
    });

    if (this.hasInactiveCountTarget) {
      this.inactiveCountTarget.textContent =
        query === "" ? this.totalInactive : inactiveVisible;
    }

    if (this.hasInactiveEmptyTarget && this.hasInactiveTableContainerTarget) {
      const showEmpty = inactiveVisible === 0 && this.totalInactive > 0;
      this.inactiveEmptyTarget.classList.toggle("d-none", !showEmpty);
      this.inactiveTableContainerTarget.classList.toggle("d-none", showEmpty);
    }
  }

  clear() {
    this.inputTarget.value = "";
    this.inputTarget.focus();
    this.filter();
  }
}
