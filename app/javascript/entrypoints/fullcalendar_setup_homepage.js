import { Calendar } from "@fullcalendar/core";
import rrulePlugin from "@fullcalendar/rrule";
import dayGridPlugin from "@fullcalendar/daygrid";
import timeGridPlugin from "@fullcalendar/timegrid";

let activeCalendar = null;

async function initHomepageCalendar() {
  const calendarEl = document.getElementById("calendar");
  if (!calendarEl) return;

  if (activeCalendar) {
    activeCalendar.destroy();
    activeCalendar = null;
  }

  try {
    const response = await fetch("/open_hours", {
      headers: { Accept: "application/json" },
    });

    if (!response.ok) return;

    const eventSources = await response.json();
    if (!eventSources || eventSources.length === 0) {
      calendarEl.innerHTML =
        "<p class='text-muted text-center py-4'>No open hours available // Aucune heure d'ouverture disponible</p>";
      return;
    }

    const isHoursPage = window.location.pathname === "/hours";
    const getView = (mobile) => {
      if (isHoursPage) {
        return mobile ? "timeGridThreeDay" : "timeGridSevenDay";
      }
      return mobile ? "timeGridTwoDay" : "timeGridFiveDay";
    };

    const initialView = getView(window.innerWidth < 1000);

    activeCalendar = new Calendar(calendarEl, {
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
        timeGridSevenDay: { type: "timeGridWeek", buttonText: "7 day" },
      },
      firstDay: 0,
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
      eventTimeFormat: {
        hour: "2-digit",
        minute: "2-digit",
        meridiem: "short",
      },
      windowResize: () => {
        const targetView = getView(window.innerWidth < 1000);
        if (activeCalendar && activeCalendar.view.type !== targetView) {
          activeCalendar.changeView(targetView);
        }
      },
    });

    activeCalendar.render();

    const checkboxContainer = document.getElementById("filters");
    if (checkboxContainer) {
      checkboxContainer.innerHTML = "";
      eventSources.forEach((source, index) => {
        const sourceId = source.id;
        const sourceName = source.events?.[0]?.extendedProps?.name;
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

        const label = document.createElement("label");
        label.className = "form-check-label mt-1";
        label.htmlFor = `filter-${sourceId}`;
        label.innerHTML = sourceName;

        checkboxWrapper.appendChild(checkbox);
        checkboxWrapper.appendChild(label);
        checkboxContainer.appendChild(checkboxWrapper);

        checkbox.addEventListener("change", (e) => {
          if (!activeCalendar) return;
          const sourceToToggle = activeCalendar.getEventSourceById(sourceId);
          if (sourceToToggle) sourceToToggle.remove();
          if (e.target.checked)
            activeCalendar.addEventSource(eventSources[index]);
        });
      });
    }
  } catch (error) {
    console.error("Error initializing calendar:", error);
  }
}

document.addEventListener("turbo:load", initHomepageCalendar);
document.addEventListener("turbo:before-cache", () => {
  if (activeCalendar) {
    activeCalendar.destroy();
    activeCalendar = null;
  }
});
