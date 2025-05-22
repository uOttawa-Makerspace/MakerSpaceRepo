import { Calendar } from "@fullcalendar/core";
import rrulePlugin from "@fullcalendar/rrule";
import timeGridPlugin from "@fullcalendar/timegrid";
import dayGridPlugin from "@fullcalendar/daygrid";
import interactionPlugin from "@fullcalendar/interaction";

import { rrulestr } from "rrule";

import { isAllDay } from "./calendar_helper.js";
import { eventClick, eventCreate } from "./unavailabilities.js";

document.addEventListener("turbo:load", async () => {
  const calendarEl = document.getElementById("calendar");

  try {
    const res = await fetch("/staff/unavailabilities/json");
    const data = await res.json();

    const events = data.map((unavailability) => {
      const event = {
        id: unavailability.id,
        start: unavailability.start_date,
        end: unavailability.end_date,
        title: unavailability.title || "Unavailable",
        allDay: isAllDay(unavailability.start_date, unavailability.end_date),
      };

      if (unavailability.recurrence_rule) {
        try {
          const rule = rrulestr(unavailability.recurrence_rule);
          event.rrule = rule.toString();
        } catch (e) {
          console.warn(
            "Invalid recurrence rule:",
            unavailability.recurrence_rule,
            e,
          );
        }
      }

      return event;
    });

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
      events: events,
      eventClick: (info) => eventClick(info, events),
      select: (info) => eventCreate(info),
    });

    calendar.render();
  } catch (error) {
    console.error("Error fetching unavailability data:", error);
  }
});
