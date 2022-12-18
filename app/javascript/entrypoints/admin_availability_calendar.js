import "flatpickr";
import { Calendar } from "@fullcalendar/core";
import "@fullcalendar/common/main.css";
import interactionPlugin from "@fullcalendar/interaction";
import timeGridPlugin from "@fullcalendar/timegrid";
import listPlugin from "@fullcalendar/list";
import bootstrap from "bootstrap";

// Modal
const unavailabilityModal = new bootstrap.Modal(
  document.getElementById("unavailabilityModal")
);

// Show Unavailabilities
let showUnavailabilities = "block";

// Inputs
const dayInput = document.getElementById("day");
const userIdInput = document.getElementById("user-id");
const startTimeInput = document.getElementById("start-time");
const endTimeInput = document.getElementById("end-time");

const startPicker = startTimeInput.flatpickr({
  enableTime: true,
  noCalendar: true,
  dateFormat: "H:i",
  time_24hr: true,
});

const endPicker = endTimeInput.flatpickr({
  enableTime: true,
  noCalendar: true,
  dateFormat: "H:i",
  time_24hr: true,
});

document.getElementById("start-time-clear").addEventListener("click", () => {
  startPicker.clear();
});

document.getElementById("end-time-clear").addEventListener("click", () => {
  endPicker.clear();
});

// Calendar Config
const calendarEl = document.getElementById("calendar");

const calendar = new Calendar(calendarEl, {
  plugins: [interactionPlugin, timeGridPlugin, listPlugin],
  customButtons: {
    addNewEvent: {
      text: "+",
      click: () => {
        unavailabilityModal.show();
      },
    },
  },
  headerToolbar: {
    left: "prev,today,next",
    center: "",
    right: "addNewEvent,timeGridWeek,timeGridDay",
  },
  views: {
    timeGridWeek: {
      dayHeaderFormat: {
        weekday: "long",
      },
    },
  },
  contentHeight: "auto",
  allDaySlot: false,
  timeZone: "America/New_York",
  initialView: "timeGridWeek",
  navLinks: true,
  selectable: true,
  selectMirror: true,
  editable: true,
  slotEventOverlap: false,
  slotMinTime: "07:00:00",
  slotMaxTime: "22:00:00",
  eventTimeFormat: {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  },
  dayMaxEvents: true,
  select: (arg) => {
    openModal(arg);
  },
  eventClick: (arg) => {
    removeEvent(arg);
  },
  eventDrop: (arg) => {
    modifyEvent(arg);
  },
  eventResize: (arg) => {
    modifyEvent(arg);
  },
  eventSources: [
    {
      id: "unavailabilities",
      url: `/admin/shifts/get_availabilities`,
    },
  ],
});

calendar.render();

// Hide/Show unavailabilities toggle
document
  .getElementById("hide-show-unavailabilities")
  .addEventListener("click", () => {
    showUnavailabilities = showUnavailabilities === "block" ? "none" : "block";
    let allEvents = calendar.getEvents();
    allEvents.forEach((event) => {
      event.setProp(
        "display",
        showUnavailabilities === "block" ? "block" : "none"
      );
    });
    [...document.getElementsByClassName("shift-hide-button")].forEach((el) => {
      el.checked = showUnavailabilities === "block";
    });
  });

// Hide/Show unavailabilities for a single staff
window.toggleVisibility = (id) => {
  let allEvents = calendar.getEvents();
  for (let ev of allEvents) {
    if (ev.extendedProps.userId === id) {
      ev.setProp(
        "display",
        document.getElementById(`user-${id}`).checked ? "block" : "none"
      );
    }
  }
};

// Update the user's color
window.updateColor = (userId, color) => {
  fetch("/admin/shifts/update_color", {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      user_id: userId,
      color: color,
      format: "json",
    }),
  })
    .then((response) => {
      if (response.ok) {
        Turbolinks.visit(window.location, { action: "replace" });
      } else {
        showToast("toast-color-update-failed");
      }
    })
    .catch((error) => {
      showToast("toast-color-update-failed");
      console.log("An error occurred: " + error.message);
    });
};

// Show the Toast
const showToast = (id) => {
  const toast = new bootstrap.Toast(document.getElementById(id));
  toast.show();
};

// Calendar CRUD
const createCalendarEvent = () => {
  fetch("/staff_availabilities", {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      staff_availability: {
        day: dayInput.value,
        start_time: startTimeInput.value,
        end_time: endTimeInput.value,
      },
      staff_id: userIdInput.value,
      format: "json",
    }),
  })
    .then((response) => response.json())
    .then((data) => {
      calendar.addEvent(
        {
          title: data.title,
          startTime: data.startTime,
          endTime: data.endTime,
          daysOfWeek: data.daysOfWeek,
          allDay: false,
          id: data.id,
          color: data.color,
          userId: userIdInput.value,
        },
        "unavailabilities"
      );
      calendar.unselect();
      unavailabilityModal.hide();
    })
    .catch((error) => {
      console.log("An error occurred: " + error.message);
    });
};

const removeEvent = (arg) => {
  if (confirm("Are you sure you want to delete this unavailability?")) {
    fetch("/staff_availabilities/" + arg.event.id, {
      method: "DELETE",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ format: "json" }),
    })
      .then((response) => {
        if (response.ok) {
          arg.event.remove();
        } else {
          console.log("An error occurred");
        }
      })
      .catch((error) => {
        console.log("An error occurred: " + error.message);
      });
  }
};

const modifyEvent = (arg) => {
  fetch("/staff_availabilities/" + arg.event.id, {
    method: "PUT",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      start_date: arg.event.start,
      end_date: arg.event.end,
      format: "json",
    }),
  })
    .then((response) => {
      if (!response.ok) {
        arg.revert();
      }
    })
    .catch((error) => {
      console.log("An error occurred: " + error.message);
    });
};

// Save event on modal save button click
document
  .getElementById("modal-save")
  .addEventListener("click", () => createCalendarEvent());

// Open modal with right values inside
const openModal = (arg) => {
  if (arg !== undefined && arg !== null) {
    startPicker.setDate(Date.parse(arg.startStr));
    endPicker.setDate(Date.parse(arg.endStr));
    dayInput.value = new Date(Date.parse(arg.startStr)).getDay();
  }

  unavailabilityModal.show();
};
