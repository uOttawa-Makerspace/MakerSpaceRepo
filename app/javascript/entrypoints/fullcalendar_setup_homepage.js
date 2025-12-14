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

    // Check if on hours page
    const isHoursPage = window.location.pathname === "/hours";
    const isMobile = window.innerWidth < 1000;

    // Determine initial view based on page and screen size
    const getView = (mobile) => {
      if (isHoursPage) {
        return mobile ? "timeGridThreeDay" : "timeGridSevenDay";
      } else {
        return mobile ? "timeGridTwoDay" : "timeGridFiveDay";
      }
    };

    const initialView = getView(isMobile);

    const calendar = new Calendar(calendarEl, {
      plugins: [timeGridPlugin, dayGridPlugin, rrulePlugin],
      initialView: initialView,
      views: {
        timeGridTwoDay: {
          type: "timeGrid",
          duration: { days: 2 },
          buttonText: "2 day",
        },
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
        timeGridSevenDay: {
          type: "timeGrid",
          duration: { days: 7 },
          buttonText: "7 day",
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
      allDaySlot: isHoursPage,
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
        const targetView = getView(isMobileView);
        const currentView = calendar.view.type;

        if (currentView !== targetView) {
          calendar.changeView(targetView);
        }
      },
    });

    calendar.render();

    // Create checkboxes for event sources
    const checkboxContainer = document.getElementById("filters");

    eventSources.forEach((source, index) => {
      const sourceId = source.id;
      const sourceName = source.events?.[0].extendedProps.name;
      const sourceColor = source.color || source.backgroundColor || "#3788d8";

      if (!sourceId || !sourceName) return;

      const checkboxWrapper = document.createElement("div");
      checkboxWrapper.className = "d-flex align-items-center gap-2";

      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.className = "form-check-input";
      checkbox.id = `filter-${sourceId}`;
      checkbox.style.backgroundColor = sourceColor;
      checkbox.style.borderColor = sourceColor;
      checkbox.style.width = "20px";
      checkbox.style.height = "20px";
      checkbox.checked = true;
      checkbox.dataset.sourceId = sourceId;

      const label = document.createElement("label");
      label.className = "form-check-label mt-1";
      label.htmlFor = `filter-${sourceId}`;
      label.innerHTML = sourceName;

      checkboxWrapper.appendChild(checkbox);
      checkboxWrapper.appendChild(label);
      checkboxContainer.appendChild(checkboxWrapper);

      // Add event listener to toggle event source
      checkbox.addEventListener("change", (e) => {
        const sourceToToggle = calendar.getEventSourceById(sourceId);

        if (sourceToToggle) {
          sourceToToggle.remove();
        }

        if (e.target.checked) {
          calendar.addEventSource(eventSources[index]);
        }
      });
    });

    console.log(`Loaded ${eventSources.length} open hours events`);
  } catch (error) {
    console.error("Error initializing calendar:", error);
  }
});
