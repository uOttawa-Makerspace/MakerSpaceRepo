import { Calendar } from "@fullcalendar/core";
import rrulePlugin from "@fullcalendar/rrule";
import timeGridPlugin from "@fullcalendar/timegrid";
import dayGridPlugin from "@fullcalendar/daygrid";

import { Tooltip } from "bootstrap";

document.addEventListener("turbo:load", async () => {
  const calendarEl = document.getElementById("calendar");
  let onlyShowMyShifts = false;

  const calendar = new Calendar(calendarEl, {
    plugins: [timeGridPlugin, dayGridPlugin, rrulePlugin],
    timeZone: "America/Toronto",
    initialView: "timeGridWeek",
    headerToolbar: {
      left: "prev,next,today toggleOthersShifts toggleEventOverlap",
      center: "title",
      right: "timeGridWeek,dayGridMonth",
    },
    slotEventOverlap: localStorage.fullCalendarEventOverlap === "true",
    customButtons: {
      toggleOthersShifts: {
        text: "Show My Shifts Only",
        click: () => {
          onlyShowMyShifts = !onlyShowMyShifts;

          calendar.getEvents().forEach((event) => {
            if (onlyShowMyShifts)
              calendar
                .getEventById(event.id)
                .setProp(
                  "display",
                  event.extendedProps.hasCurrentUser ? "auto" : "none",
                );
            else calendar.getEventById(event.id).setProp("display", "auto");
          });

          document.querySelector(".fc-toggleOthersShifts-button").innerHTML =
            onlyShowMyShifts ? "Show My Shifts Only" : "Show All Shifts";
        },
      },
      toggleEventOverlap: {
        text: "",
        click: () => {
          localStorage.fullCalendarEventOverlap =
            !calendar.getOption("slotEventOverlap");

          calendar.setOption(
            "slotEventOverlap",
            !calendar.getOption("slotEventOverlap"),
          );

          document.querySelector(".fc-toggleEventOverlap-button").innerHTML =
            calendar.getOption("slotEventOverlap")
              ? "Disable Event Overlap"
              : "Enable Event Overlap";
        },
      },
    },
    scrollTime: "07:00:00",
    height: "80vh",
    eventSources:
      "/staff/my_calendar/json/" + document.getElementById("space_id").value,
    eventDidMount: (info) => {
      // fade in event
      requestAnimationFrame(() => {
        info.el.classList.add("fade-in");
      });

      // create event tooltip
      new Tooltip(info.el, {
        title:
          info.event.title +
          (info.event.extendedProps.description
            ? `<br><i>${info.event.extendedProps.description}</i>`
            : ""),
        html: true,
      });

      // add user color bg gradient
      if (info.event.extendedProps.background) {
        info.el.setAttribute(
          "style",
          `
          background: ${info.event.extendedProps.background}`,
        );
      }
    },
    initialDate: localStorage.fullCalendarDefaultDateStaffCalendar,
    datesSet: (info) => {
      // recall dates on refresh
      const date = new Date(info.view.currentStart);
      localStorage.fullCalendarDefaultDateStaffCalendar = date.toISOString();
    },
  });

  // Render and SHOW IT!!!
  document.getElementById("calendar_container").style.display = "block";
  document.getElementById("spinner_container").style.display = "none";
  calendar.render();

  // Set button text
  document.querySelector(".fc-toggleEventOverlap-button").innerHTML =
    calendar.getOption("slotEventOverlap")
      ? "Disable Event Overlap"
      : "Enable Event Overlap";
});
