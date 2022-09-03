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
window.toggleVisibility = (name) => {
  document.getElementById(name).innerText = `${
    document.getElementById(name).innerText == "Hide" ? "Show" : "Hide"
  }`;
  let staff_name = document.getElementById(name).dataset.staffname;
  let allEvents = calendar.getEvents();
  for (let ev of allEvents) {
    if (ev.title.startsWith(staff_name)) {
      ev.setProp(
        "display",
        document.getElementById(name).innerText == "Show" ? "none" : "block"
      );
    }
  }
};
