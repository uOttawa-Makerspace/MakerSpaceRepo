import { Calendar } from "@fullcalendar/core";
import "@fullcalendar/common/main.css";
import timeGridPlugin from "@fullcalendar/timegrid";
import listPlugin from "@fullcalendar/list";
import googleCalendarPlugin from "@fullcalendar/google-calendar";

// Time slot constants
const SLOT_MIN_TIME = new Date(new Date().setHours(7, 0, 0, 0));
const SLOT_MAX_TIME = new Date(new Date().setHours(23, 0, 0, 0));

// Show
let sourceShow = {
  google: document.getElementById("hide-show-google-events")
    ? "block"
    : "block",
};

let hiddenIds = {};
let events = 0;

// Calendar Config
let calendarEl = document.getElementById("calendar");
let calendar;

document.addEventListener("turbo:load", () => {
  calendarEl.remove();
  calendarEl = document.createElement("div");
  calendarEl.id = "calendar";
  document.getElementById("calendar-container").appendChild(calendarEl);
  events = 0;

  fetch("/admin/shifts/get_external_staff_needed", {
    method: "GET",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
  })
    .then((res) => res.json())
    .then(() => {
      calendar = new Calendar(calendarEl, {
        plugins: [timeGridPlugin, listPlugin, googleCalendarPlugin],
        headerToolbar: {
          left: "prev,today,next",
          right: "timeGridWeek,timeGridDay",
        },
        contentHeight: "auto",
        allDaySlot: false,
        timeZone: "America/New_York",
        initialView: "timeGridWeek",
        selectable: false,
        slotMinTime: SLOT_MIN_TIME.toTimeString().split(" ")[0],
        slotMaxTime: SLOT_MAX_TIME.toTimeString().split(" ")[0],
        eventTimeFormat: {
          hour: "2-digit",
          minute: "2-digit",
          hour12: false,
        },
        editable: false,
        dayMaxEvents: true,
        eventSources: [
          {
            id: "shifts",
            url: "/admin/shifts/get_shifts",
          },
          {
            id: "google",
            googleCalendarApiKey: "AIzaSyCMNxnP0pdKHtZaPBJAtfv68A2h6qUeuW0",
            googleCalendarId:
              "c_d7liojb08eadntvnbfa5na9j98@group.calendar.google.com",
            color: "rgba(255,31,31,0.4)",
            editable: false,
          },
        ],
        eventSourceSuccess: (content) => {
          content.forEach((event) => {
            if (hiddenIds[event.userId] === "none") {
              event.display = "none";
            } else if (hiddenIds[event.userId] === "block") {
              event.display = "block";
            } else {
            }
          });
          hideShowEvents("check");
          return content;
        },
        eventDidMount: (info) => {
          if (info.event.extendedProps.color) {
            info.el.style.background = info.event.extendedProps.color;
            info.el.style.borderColor = "transparent";
          }
        },
      });
      calendar.render();
    });
});

// Hide/Show Events
const hideShowEvents = (eventName) => {
  eventName === "check" ? (events += 1) : events;

  if (events >= Object.keys(calendar.currentData.eventSources).length) {
    document.getElementById("spinner").classList.add("d-none");
  }

  let allEvents = calendar.getEvents();
  if (eventName !== "check") {
    sourceShow[eventName] = sourceShow[eventName] === "none" ? "block" : "none";
  }

  let eventsToProcess = [];
  if (eventName === "check") {
    eventsToProcess = allEvents.filter((ev) =>
      sourceShow.hasOwnProperty(ev.source.id)
    );
  } else {
    eventsToProcess = allEvents.filter((ev) => ev.source.id === eventName);
  }

  calendar.batchRendering(() => {
    for (let ev of eventsToProcess) {
      let display = sourceShow[ev.source.id] || "block";
      ev.setProp(
        "display",
        hiddenIds[ev.extendedProps.userId] === "none" ? "none" : display
      );
    }
  });
};
