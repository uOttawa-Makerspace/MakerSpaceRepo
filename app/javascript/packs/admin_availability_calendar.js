import { Calendar } from "@fullcalendar/core";
import "@fullcalendar/common/main.css";
import interactionPlugin from "@fullcalendar/interaction";
import timeGridPlugin from "@fullcalendar/timegrid";
import listPlugin from "@fullcalendar/list";

let calendarEl = document.getElementById("calendar");
const urlParams = new URLSearchParams(window.location.search);
let show = "block";
let calendar = new Calendar(calendarEl, {
  plugins: [interactionPlugin, timeGridPlugin, listPlugin],
  headerToolbar: {
    left: "prev,today,next",
    center: "",
    right: "timeGridWeek,timeGridDay",
  },
  views: {
    timeGridWeek: {
      dayHeaderFormat: {
        weekday: "long",
      },
    },
  },
  contentHeight: "auto",
  allDaySlot: false,
  timeZone: "America/New_York",
  initialView: "timeGridWeek",
  navLinks: true,
  slotEventOverlap: false,
  slotMinTime: "07:00:00",
  slotMaxTime: "22:00:00",
  eventTimeFormat: {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  },
  dayMaxEvents: true,
  eventClick: function (info) {
    alert("Event: " + info.event.title);
  },
  eventSources: [
    {
      url: `/admin/shifts/get_availabilities`,
    },
  ],
});

calendar.render();

document
  .getElementById("hide-show-unavailabilities")
  .addEventListener("click", () => {
    show = show === "block" ? "none" : "block";
    let allEvents = calendar.getEvents();
    allEvents.forEach((event) => {
      event.setProp("display", show === "block" ? "block" : "none");
    });
    [...document.getElementsByClassName("shift-hide-button")].forEach(
      (item) => {
        item.innerText = show === "block" ? "Hide" : "Show";
      }
    );
    document.getElementById("hide-show-unavailabilities").innerText =
      show === "block" ? "Hide Unavailabilities" : "Show Unavailabilities";
  });
window.toggleVisibility = (id) => {
  let allEvents = calendar.getEvents();
  for (let ev of allEvents) {
    if (ev.id == id) {
      ev.setProp(
        "display",
        document.getElementById(`user-${id}`).checked ? "block" : "none"
      );
    }
  }
};

window.updateColor = (id, color) => {
  fetch("/admin/shifts/update_color", {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      id: id,
      color: color,
      format: "json",
    }),
  })
    .then((response) => {
      if (response.ok) {
        const toast = new bootstrap.Toast(
          document.getElementById("toast-color-update-success")
        );
        toast.show();
      } else {
        const toast = new bootstrap.Toast(
          document.getElementById("toast-color-update-failed")
        );
        toast.show();
      }
    })
    .catch((error) => {
      const toast = new bootstrap.Toast(
        document.getElementById("toast-color-update-failed")
      );
      toast.show();
      console.log("An error occurred: " + error.message);
    });
};
