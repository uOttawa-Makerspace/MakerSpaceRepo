import { addEventClick } from "./calendar_helper";
import "./fullcalendar_setup_admin";
import "./manage_calendar_events";
import "flatpickr";

document.addEventListener("turbo:load", () => {
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
  fetch("/admin/calendar/update_color", {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      user_id: userId,
      color: color,
      format: "json",
    }),
  })
    .then((res) => {
      // Yippee!
    })
    .catch((error) => {
      console.error("An error occurred: " + error.message);
    });
}

/* For the event modal */
document.addEventListener("turbo:load", () => {
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
