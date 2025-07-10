import DataTable from "datatables.net-bs5";
import "datatables.net-bs5/css/dataTables.bootstrap5.min.css";

document.addEventListener("turbo:load", () => {
  const dt = new DataTable(".table:not(.notDataTable)", {
    order: [[4, "desc"]],
    pageLength: 25,
  });

  const dateRangeSelect = document.getElementById("date_range");
  const jobTypeCheckboxes = document.querySelectorAll(
    "input[name='job_type_filter[]']",
  );
  const jobStatusCheckboxes = document.querySelectorAll(
    "input[name='job_status_filter[]']",
  );
  const assignedToCheckboxes = document.querySelectorAll(
    "input[name='assigned_to_filter[]']",
  );
  const activeFiltersContainer = document.getElementById("active-filters");
  const filterTags = document.getElementById("filter-tags");
  const clearFiltersBtn = document.getElementById("clear-filters");

  dateRangeSelect.addEventListener("change", (e) => {
    handleDateRangeChange(e.target);
    applyFilters();
  });
  jobTypeCheckboxes.forEach((cb) =>
    cb.addEventListener("change", applyFilters),
  );
  jobStatusCheckboxes.forEach((cb) =>
    cb.addEventListener("change", applyFilters),
  );
  assignedToCheckboxes.forEach((cb) =>
    cb.addEventListener("change", applyFilters),
  );
  clearFiltersBtn.addEventListener("click", () => {
    const defaultDateRadio = document.getElementById("default_date");
    defaultDateRadio.checked = true;
    handleDateRangeChange(defaultDateRadio);

    jobTypeCheckboxes.forEach((cb) => (cb.checked = false));
    jobStatusCheckboxes.forEach((cb) => (cb.checked = false));
    assignedToCheckboxes.forEach((cb) => (cb.checked = false));
    applyFilters();
  });

  function getSelectedValues(checkboxes) {
    return Array.from(checkboxes)
      .filter((cb) => cb.checked)
      .map((cb) => cb.value);
  }

  function buildRegexSearch(values) {
    if (values.length === 0) return "";
    return values.map((v) => v).join("|");
  }

  function applyFilters() {
    const selectedTypes = getSelectedValues(jobTypeCheckboxes);
    const selectedStatuses = getSelectedValues(jobStatusCheckboxes);
    const selectedAssignedTo = getSelectedValues(assignedToCheckboxes);

    const typeRegex = buildRegexSearch(selectedTypes);
    const statusRegex = buildRegexSearch(selectedStatuses);
    const assignedToRegex = buildRegexSearch(selectedAssignedTo);

    DataTable.ext.search.push((_settings, data, _dataIndex) => {
      const dateStr = data[4];
      const date = new Date(dateStr);
      const now = new Date();
      const diffDays = Math.floor((now - date) / (1000 * 60 * 60 * 24));

      const lastXDays = parseInt(
        document.getElementById("computed_days").value,
      );

      return diffDays <= lastXDays;
    }); // date range
    dt.column(5).search(typeRegex, true, false); // job_type
    dt.column(6).search(statusRegex, true, false); // job_status
    dt.column(7).search(assignedToRegex, false, false); // assigned_to

    dt.draw();

    updateFilterDisplay(selectedTypes, selectedStatuses, selectedAssignedTo);
  }

  function updateFilterDisplay(types, statuses, assignedTos) {
    const selectedRadio = document.querySelector(
      'input[name="date_range"]:checked',
    );
    const labelText = selectedRadio
      ? selectedRadio.parentElement.textContent.trim()
      : null;

    const hasFilters =
      labelText !== "All time" ||
      types.length > 0 ||
      statuses.length > 0 ||
      assignedTos.length > 0;

    if (hasFilters) {
      activeFiltersContainer.classList.remove("d-none");
      filterTags.innerHTML = "";

      [labelText, ...types, ...statuses, ...assignedTos].forEach((value) => {
        if (value == "All time") return;
        if (value == "Assign") value = "Unassigned"; // Special case for "Assign"

        const badge = document.createElement("span");
        badge.className = "badge bg-secondary me-1";
        badge.textContent = value;
        filterTags.appendChild(badge);
      });
    } else {
      activeFiltersContainer.classList.add("d-none");
      filterTags.innerHTML = "";
    }
  }

  // Methods for date range
  function handleDateRangeChange(radio) {
    const computedInput = document.getElementById("computed_days");

    if (radio.value === "all") {
      computedInput.value = "1000000"; // good enough :-)
    } else if (radio.value === "semester") {
      computedInput.value = daysSinceMostRecentSemesterStart();
    } else {
      computedInput.value = radio.value;
    }
  }

  function daysSinceMostRecentSemesterStart() {
    const today = new Date();
    const year = today.getFullYear();

    const semesterStartDates = [
      new Date(year, 0, 1), // Jan 1 winter sem
      new Date(year, 4, 1), // May 1 spring summer sem
      new Date(year, 8, 1), // Sept 1 fall sem
    ];

    const mostRecent = semesterStartDates
      .filter((d) => d <= today)
      .sort((a, b) => b - a)[0];

    const diffTime = today - mostRecent;
    return Math.floor(diffTime / (1000 * 60 * 60 * 24));
  }
});
