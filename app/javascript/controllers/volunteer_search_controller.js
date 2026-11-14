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

    this.filterActive(query);
    this.filterInactive(query);
  }

  filterActive(query) {
    const visible = showMatchingRows(this.activeRowTargets, query);

    if (this.hasActiveCountTarget) {
      this.activeCountTarget.textContent =
        query === "" ? this.totalActive : visible;
    }

    if (this.hasActiveEmptyTarget && this.hasActiveTableContainerTarget) {
      toggleEmptyMessage(
        this.activeEmptyTarget,
        this.activeTableContainerTarget,
        visible === 0 && this.totalActive > 0,
      );
    }
  }

  filterInactive(query) {
    const visible = showMatchingRows(this.inactiveRowTargets, query);

    if (this.hasInactiveCountTarget) {
      this.inactiveCountTarget.textContent =
        query === "" ? this.totalInactive : visible;
    }

    if (this.hasInactiveEmptyTarget && this.hasInactiveTableContainerTarget) {
      toggleEmptyMessage(
        this.inactiveEmptyTarget,
        this.inactiveTableContainerTarget,
        visible === 0 && this.totalInactive > 0,
      );
    }
  }

  clear() {
    this.inputTarget.value = "";
    this.inputTarget.focus();
    this.filter();
  }
}

// Hides the rows whose text does not contain the query (every row matches an
// empty query) and returns how many stay visible.
function showMatchingRows(rows, query) {
  let visible = 0;
  rows.forEach((row) => {
    const match = query === "" || row.textContent.toLowerCase().includes(query);
    row.classList.toggle("d-none", !match);
    if (match) visible++;
  });
  return visible;
}

// Shows the no-match message in place of the table, or the table in place of it.
function toggleEmptyMessage(empty, tableContainer, showEmpty) {
  empty.classList.toggle("d-none", !showEmpty);
  tableContainer.classList.toggle("d-none", showEmpty);
}
