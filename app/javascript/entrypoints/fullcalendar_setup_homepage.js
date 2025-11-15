import { Calendar } from "@fullcalendar/core";
import rrulePlugin from "@fullcalendar/rrule";
import dayGridPlugin from "@fullcalendar/daygrid";
import timeGridPlugin from "@fullcalendar/timegrid";

document.addEventListener("DOMContentLoaded", async function () {
  const calendarEl = document.getElementById("calendar");

  if (!calendarEl) return;

  try {
    const response = await fetch("/open_hours").catch((error) => {
      console.error("Failed to fetch open hours:", error);
      return null;
    });

    if (!response || !response.ok) {
      console.error("Failed to load open hours");
      return;
    }

    const eventSources = await response.json();

    if (!eventSources || eventSources.length === 0) {
      console.log("No open hours found");
      calendarEl.innerHTML =
        "<p class='text-muted text-center py-4'>No open hours available // Aucune heure d'ouverture disponible</p>";
      return;
    }

    // Determine initial view based on screen size
    const isMobile = window.innerWidth < 1000;
    const initialView = isMobile ? "timeGridThreeDay" : "timeGridFiveDay";

    const calendar = new Calendar(calendarEl, {
      plugins: [timeGridPlugin, dayGridPlugin, rrulePlugin],
      initialView: initialView,
      views: {
        timeGridThreeDay: {
          type: "timeGrid",
          duration: { days: 3 },
          buttonText: "3 day",
        },
        timeGridFiveDay: {
          type: "timeGrid",
          duration: { days: 5 },
          buttonText: "5 day",
        },
      },
      headerToolbar: {
        left: "prev",
        center: "title",
        right: "next",
      },
      eventSources: eventSources,
      expandRows: true,
      contentHeight: "auto",
      stickyHeaderDates: false,
      timeZone: "America/Toronto",
      nowIndicator: true,
      slotEventOverlap: false,
      allDaySlot: false,
      slotMinTime: "08:00:00",
      slotMaxTime: "22:00:00",
      slotDuration: "01:00:00",
      slotLabelInterval: "01:00:00",
      slotMinHeight: 40,
      eventTimeFormat: {
        hour: "2-digit",
        minute: "2-digit",
        meridiem: "short",
      },
      windowResize: (view) => {
        const isMobileView = window.innerWidth < 1000;
        const currentView = calendar.view.type;

        if (isMobileView && currentView === "timeGridFiveDay") {
          calendar.changeView("timeGridThreeDay");
        } else if (!isMobileView && currentView === "timeGridThreeDay") {
          calendar.changeView("timeGridFiveDay");
        }
      },
    });

    calendar.render();
    console.log(`Loaded ${eventSources.length} open hours events`);
  } catch (error) {
    console.error("Error initializing calendar:", error);
  }
});
