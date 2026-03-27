import { createConsumer } from "@rails/actioncable";

const consumer = createConsumer();

document.addEventListener("DOMContentLoaded", () => {
  const consoleEl = document.getElementById("tap-box-console");
  const consoleBody = document.getElementById("console-body");
  const statusBadge = document.getElementById("connection-status");
  const filterType = document.getElementById("filter-event-type");
  const filterSearch = document.getElementById("filter-search");
  const btnClear = document.getElementById("btn-clear-console");

  // Page guard — only run on the console page
  if (!consoleEl) return;

  // Connection status via thin channel (content arrives via Turbo Streams)
  consumer.subscriptions.create("TapBoxConsoleChannel", {
    connected() {
      statusBadge.className = "badge bg-success";
      statusBadge.textContent = "● Connected";
    },
    disconnected() {
      statusBadge.className = "badge bg-danger";
      statusBadge.textContent = "● Disconnected";
    },
    rejected() {
      statusBadge.className = "badge bg-danger";
      statusBadge.textContent = "● Rejected";
    },
  });

  // Watch for Turbo Stream appended rows
  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        if (node.nodeType === Node.ELEMENT_NODE) {
          const emptyState = document.getElementById("empty-state");
          if (emptyState) emptyState.remove();

          applyFiltersToRow(node);

          // Auto-scroll to TOP so the newest row is visible
          const nearTop = consoleEl.scrollTop < 100;
          if (nearTop) consoleEl.scrollTop = 0;

          // Trim oldest rows from the BOTTOM
          while (consoleBody.children.length > 1000) {
            consoleBody.removeChild(consoleBody.lastElementChild);
          }
        }
      }
    }
  });
  observer.observe(consoleBody, { childList: true });

  // Start at the top (newest rows) on initial load
  consoleEl.scrollTop = 0;

  function applyFiltersToRow(row) {
    const typeVal = filterType.value;
    const searchVal = filterSearch.value.toLowerCase().trim();
    let visible = true;
    if (typeVal && row.dataset.eventType !== typeVal) visible = false;
    if (
      searchVal &&
      row.dataset.searchable &&
      !row.dataset.searchable.includes(searchVal)
    )
      visible = false;
    row.style.display = visible ? "" : "none";
  }

  function applyAllFilters() {
    consoleBody.querySelectorAll("tr").forEach(applyFiltersToRow);
  }

  filterType.addEventListener("change", applyAllFilters);
  filterSearch.addEventListener("input", applyAllFilters);

  btnClear.addEventListener("click", () => {
    consoleBody.innerHTML = "";
  });
});
