import { Calendar } from "@fullcalendar/core";
import "@fullcalendar/common/main.css";
import interactionPlugin from "@fullcalendar/interaction";
import timeGridPlugin from "@fullcalendar/timegrid";
import listPlugin from "@fullcalendar/list";

// Time slot constants
const SLOT_MIN_TIME = new Date(new Date().setHours(7, 0, 0, 0));
const SCROLL_TO_TIME = new Date(new Date().setHours(7, 0, 0, 0));
const SLOT_MAX_TIME = new Date(new Date().setHours(23, 0, 0, 0));

document.addEventListener("DOMContentLoaded", function () {
  var calendarEl = document.getElementById("calendar");

  var calendar = new Calendar(calendarEl, {
    plugins: [timeGridPlugin, interactionPlugin, listPlugin],
    headerToolbar: {
      left: "prev,today,next",
      right: "timeGridWeek,timeGridDay",
    },
    contentHeight: "auto",
    slotEventOverlap: false,
    allDaySlot: false,
    timeZone: "America/New_York",
    initialView: "timeGridWeek",
    scrollTime: SCROLL_TO_TIME.toTimeString().split(" ")[0],
    slotMinTime: SLOT_MIN_TIME.toTimeString().split(" ")[0],
    slotMaxTime: SLOT_MAX_TIME.toTimeString().split(" ")[0],
    eventTimeFormat: {
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    },
    dayMaxEvents: true,
    events: fetchShiftsData,
  });
  calendar.render();
});

function fetchShiftsData(info, successCallback, failureCallback) {
  fetch("/staff/shifts_schedule/get_shifts")
    .then((response) => response.json())
    .then((shiftsData) => {
      successCallback(shiftsData);
      document.getElementById("spinner").style.display = "none";
    })
    .catch((error) => {
      console.error("Error fetching shifts:", error);
      failureCallback(error);
      document.getElementById("spinner").style.display = "none";
    });
}
