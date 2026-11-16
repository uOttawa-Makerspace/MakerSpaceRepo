// app/javascript/entrypoints/volunteer_task_requests.js
import { reportFailure, requestText } from "../src/request_error";

function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}

document.addEventListener("turbo:load", function () {
  const reqContainer = document.getElementById("volunteerTaskRequestsIndex");
  if (!reqContainer) return;

  // 1. Synchronize Tab selection to URL query params
  const tabButtons = reqContainer.querySelectorAll(
    '#requestStatusTabs button[data-bs-toggle="pill"]',
  );
  tabButtons.forEach((tabBtn) => {
    tabBtn.addEventListener("shown.bs.tab", (e) => {
      const tabName = e.target.getAttribute("data-tab-name") || "pending";
      const url = new URL(window.location);
      url.searchParams.set("tab", tabName);
      window.history.replaceState({}, "", url);
    });
  });

  // Replaces the results list with the server's rendered HTML for the search.
  function showResults(path, param, value, listClass) {
    requestText(`${path}?${param}=${encodeURIComponent(value)}`, {
      headers: { Accept: "text/html" },
    })
      .then((html) => {
        const target = reqContainer.querySelector(listClass);
        if (target) target.innerHTML = html;
      })
      .catch(reportFailure);
  }

  // 2. Debounced search for Pending Requests
  const pendingSearch = document.getElementById("search_pending");
  if (pendingSearch) {
    const searchPendingDebounced = debounce(
      (val) =>
        showResults(
          "/volunteer_task_requests/search_pending",
          "search_pending",
          val,
          ".pending-requests",
        ),
      300,
    );

    pendingSearch.addEventListener("input", (e) =>
      searchPendingDebounced(e.target.value),
    );
  }

  // 3. Debounced search for Processed History
  const processedSearch = document.getElementById("search_processed");
  if (processedSearch) {
    const searchProcessedDebounced = debounce(
      (val) =>
        showResults(
          "/volunteer_task_requests/search_processed",
          "search_processed",
          val,
          ".processed-requests",
        ),
      300,
    );

    processedSearch.addEventListener("input", (e) =>
      searchProcessedDebounced(e.target.value),
    );
  }
});
