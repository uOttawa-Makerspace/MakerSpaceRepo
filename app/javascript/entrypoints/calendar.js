import { addEventClick } from "../src/calendar_helper";
import "../src/manage_calendar_events";
import "flatpickr";
import { flatpickrOptions } from "../src/page_locale.js";
import { csrfHeaders } from "../src/csrf";
import { onPageLoad } from "../src/on_page";
import { showToast } from "../src/toast";

onPageLoad("#addEventButton", () => {
  document
    .getElementById("addEventButton")
    .addEventListener("click", addEventClick);

  // Staff colors
  document
    .querySelectorAll(".staff_color_select")
    .forEach((input) =>
      input.addEventListener("change", (e) =>
        updateColor(e.target.dataset.user, e.target.value),
      ),
    );

  document.getElementById("refresh_calendar").addEventListener("click", () => {
    Turbo.visit(window.location, { action: "replace" });
  });
});

function updateColor(userId, color) {
  const notSaved = /** @type {HTMLElement} */ (
    document.querySelector("[data-color-not-saved]")
  ).dataset.colorNotSaved;

  fetch("/admin/calendar/update_color", {
    method: "POST",
    headers: csrfHeaders({
      Accept: "application/json",
      "Content-Type": "application/json",
    }),
    body: JSON.stringify({
      user_id: userId,
      color: color,
      format: "json",
    }),
  })
    .then(async (res) => {
      if (res.ok) return;
      const body = await res.json().catch(() => ({}));
      showToast(body.error ? `${notSaved} ${body.error}` : notSaved, {
        type: "error",
      });
    })
    .catch(() => showToast(notSaved, { type: "error" }));
}

/* For the event modal */
onPageLoad("#addEventButton", () => {
  flatpickr(
    "#source_range",
    flatpickrOptions(document, { mode: "range", dateFormat: "Y-m-d" }),
  );

  flatpickr(
    "#target_date",
    flatpickrOptions(document, { dateFormat: "Y-m-d" }),
  );
});
