import { Calendar } from "@fullcalendar/core";
import rrulePlugin from "@fullcalendar/rrule";
import timeGridPlugin from "@fullcalendar/timegrid";
import dayGridPlugin from "@fullcalendar/daygrid";
import interactionPlugin from "@fullcalendar/interaction";

import { eventClick, eventCreate } from "./unavailabilities_helpers.js";

document.addEventListener("turbo:load", async () => {
  const calendarEl = document.getElementById("calendar");

  const calendar = new Calendar(calendarEl, {
    plugins: [timeGridPlugin, dayGridPlugin, rrulePlugin, interactionPlugin],
    timeZone: "America/Toronto",
    initialView: "timeGridWeek",
    headerToolbar: {
      left: "prev,next,today",
      center: "title",
      right: "timeGridWeek,dayGridMonth",
    },
    scrollTime: "07:00:00",
    selectable: true,
    selectMirror: true,
    selectMinDistance: "30",
    height: "80vh",
    events: "/staff/unavailabilities/json",
    eventClick: (info) => eventClick(info.event),
    select: (info) => eventCreate(info),
    eventDidMount: (info) => {
      // fade in event
      requestAnimationFrame(() => {
        info.el.classList.add("fade-in");
      });
    },
    initialDate: localStorage.fullCalendarDefaultDateStaffUnavailabilities,
    datesSet: (info) => {
      // recall dates on refresh
      const date = new Date(info.view.currentStart);
      localStorage.fullCalendarDefaultDateStaffUnavailabilities =
        date.toISOString();
    },
  });

  // Render and SHOW IT!!!
  document.getElementById("calendar_container").style.display = "block";
  document.getElementById("spinner_container").style.display = "none";
  calendar.render();
});
