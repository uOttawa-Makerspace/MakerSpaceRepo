import { Calendar } from "@fullcalendar/core";
import rrulePlugin from "@fullcalendar/rrule";
import timeGridPlugin from "@fullcalendar/timegrid";
import dayGridPlugin from "@fullcalendar/daygrid";
import interactionPlugin from "@fullcalendar/interaction";

import { eventClick, eventCreate } from "./unavailabilities.js";

document.addEventListener("turbo:load", async () => {
  const calendarEl = document.getElementById("calendar");

  const calendar = new Calendar(calendarEl, {
    plugins: [timeGridPlugin, dayGridPlugin, rrulePlugin, interactionPlugin],
    initialView: "timeGridWeek",
    headerToolbar: {
      left: "prev,next,today",
      center: "title",
      right: "timeGridWeek,dayGridMonth",
    },
    scrollTime: "08:00:00",
    selectable: true,
    selectMirror: true,
    selectMinDistance: "30",
    height: "80vh",
    events: "/staff/unavailabilities/json",
    eventClick: (info) => eventClick(info, events),
    select: (info) => eventCreate(info),
    initialDate: localStorage.fullCalendarDefaultDateStaffUnavailabilities,
    datesSet: (info) => {
      // recall dates on refresh
      const date = new Date(info.view.currentStart);
      localStorage.fullCalendarDefaultDateStaffUnavailabilities =
        date.toISOString();
    },
  });

  calendar.render();
});
