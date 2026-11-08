import { addEventClick } from "../src/calendar_helper";
import "../src/fullcalendar_setup_admin";
import "../src/manage_calendar_events";
import "flatpickr";
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
  const fp1 = flatpickr("#source_range", {
    mode: "range",
    dateFormat: "Y-m-d",
  });

  const fp2 = flatpickr("#target_date", {
    dateFormat: "Y-m-d",
  });

  let copyEventsModal = document.getElementById("copyEventsModal");
  if (copyEventsModal) {
    copyEventsModal.addEventListener("hide.bs.modal", (e) => {
      fp1.flatpickr().destroy();
      fp2.flatpickr().destroy();
    });
  }
});
