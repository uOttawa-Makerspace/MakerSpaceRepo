import "flatpickr";
import { Calendar } from "@fullcalendar/core";
import "@fullcalendar/common/main.css";
import interactionPlugin from "@fullcalendar/interaction";
import timeGridPlugin from "@fullcalendar/timegrid";
import listPlugin from "@fullcalendar/list";
import { Modal, Toast } from "bootstrap";
import { Turbo } from "@hotwired/turbo-rails";

// Modal
const unavailabilityModal = new Modal(
  document.getElementById("unavailabilityModal")
);

const modalTitle = document.getElementById("modal-title");
const modalDelete = document.getElementById("modal-delete");
const unavailabilityId = document.getElementById("unavailability-id");

// Show state
let showUnavailabilities = "block";
let hiddenIds = {};
const urlParams = new URLSearchParams(window.location.search);
const time_period_id = urlParams.get("time_period_id");

// Inputs
const dayInput = document.getElementById("day");
const userIdInput = document.getElementById("user-id");
const timePeriodIdInput = document.getElementById("time-period-id");
const startTimeInput = document.getElementById("start-time");
const startDateInput = document.getElementById("start-date");
const endTimeInput = document.getElementById("end-time");
const endDateInput = document.getElementById("end-date");
const recurringInput = document.getElementById("recurring");

const startTimePicker = startTimeInput.flatpickr({
  enableTime: true,
  noCalendar: true,
  dateFormat: "H:i",
  time_24hr: true,
});

const endTimePicker = endTimeInput.flatpickr({
  enableTime: true,
  noCalendar: true,
  dateFormat: "H:i",
  time_24hr: true,
});

const startDatePicker = startDateInput.flatpickr({
  enableTime: false,
  noCalendar: false,
  dateFormat: "Y-m-d",
});

const endDatePicker = endDateInput.flatpickr({
  enableTime: false,
  noCalendar: false,
  dateFormat: "Y-m-d",
});

recurringInput.addEventListener("change", function () {
  if (this.checked) {
    dayInput.parentElement.style.display = "block";
    startDateInput.parentElement.parentElement.style.display = "none";
    endDateInput.parentElement.parentElement.style.display = "none";
  } else {
    dayInput.parentElement.style.display = "none";
    startDateInput.parentElement.parentElement.style.display = "block";
    endDateInput.parentElement.parentElement.style.display = "block";
  }
});

document.getElementById("start-time-clear").addEventListener("click", () => {
  startTimePicker.clear();
});

document.getElementById("end-time-clear").addEventListener("click", () => {
  endTimePicker.clear();
});

document.getElementById("start-date-clear").addEventListener("click", () => {
  startDatePicker.clear();
});

document.getElementById("end-date-clear").addEventListener("click", () => {
  endDatePicker.clear();
});

// Calendar Config
const calendarEl = document.getElementById("calendar");

const calendar = new Calendar(calendarEl, {
  plugins: [interactionPlugin, timeGridPlugin, listPlugin],
  customButtons: {
    addNewEvent: {
      text: "+",
      click: () => {
        openModal(null);
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
        weekday: "short",
        month: "2-digit",
        day: "2-digit",
        omitCommas: true,
      },
    },
    timeGridDay: {
      dayHeaderFormat: {
        weekday: "long",
        month: "2-digit",
        day: "2-digit",
        omitCommas: true,
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
    editModal(arg);
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
      url: `/admin/shifts/get_availabilities${
        time_period_id ? "?time_period_id=" + time_period_id : ""
      }`,
    },
  ],
  eventSourceSuccess: (content, xhr) => {
    content.forEach((event) => {
      if (hiddenIds[event.userId] === "none") {
        event.display = "none";
      } else if (hiddenIds[event.userId] === "block") {
        event.display = "block";
      } else {
        event.display = showUnavailabilities;
      }
    });
    return content;
    // The events do not respect the display property
    // hideShowEvents('check', 'check');
  },
});

calendar.render();

// Hide/Show Events
const hideShowEvents = (event, eventName) => {
  let allEvents = calendar.getEvents();
  for (let ev of allEvents) {
    if (eventName === "id") {
      if (ev.extendedProps.userId === event) {
        ev.setProp("display", hiddenIds[event] === "block" ? "block" : "none");
      }
    } else {
      if (hiddenIds[ev.extendedProps.userId] === "none") {
        ev.setProp("display", "none");
        continue;
      }
      ev.setProp("display", showUnavailabilities);
    }
  }
  if (eventName === "unavailabilities") {
    [...document.getElementsByClassName("shift-hide-button")].forEach((el) => {
      let id = el.id.split("-")[1];
      if (!(hiddenIds[id] === "none")) {
        el.checked = showUnavailabilities === "block";
      }
      showUnavailabilities = document.getElementById(
        "hide-show-unavailabilities"
      ).checked
        ? "block"
        : "none";
    });
  } else if (eventName === "id") {
    document.querySelectorAll(`[data-user-id="${event}"]`).forEach((el) => {
      el.checked = hiddenIds[event] === "block";
    });
  }
  if (eventName === "check") {
    for (let e of calendar.getEvents()) {
      e.setProp("display", showUnavailabilities);
    }
  }
};

// Hide/Show unavailabilities toggle
document
  .getElementById("hide-show-unavailabilities")
  .addEventListener("click", () => {
    showUnavailabilities = showUnavailabilities === "block" ? "none" : "block";
    hideShowEvents(showUnavailabilities, "unavailabilities");
  });

// Hide/Show unavailabilities for a single staff
window.toggleVisibility = (id) => {
  hiddenIds[id] = document.getElementById(`user-${id}`).checked
    ? "block"
    : "none";
  hideShowEvents(id, "id");
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
        Turbo.visit(window.location, { action: "replace" });
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
  const toast = new Toast(document.getElementById(id));
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
        time_period_id: timePeriodIdInput.value,
        start_time: startTimeInput.value,
        start_date: startDateInput.value,
        end_time: endTimeInput.value,
        end_date: endDateInput.value,
        recurring: recurringInput.checked,
      },
      staff_id: userIdInput.value,
      format: "json",
    }),
  })
    .then((response) => response.json())
    .then((data) => {
      if (data.recurring) {
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
            recurring: true,
            startRecur: data.timePeriodStart,
            endRecur: data.timePeriodEnd,
          },
          "unavailabilities"
        );
      } else {
        calendar.addEvent(
          {
            title: data.title,
            start: data.startTime,
            end: data.endTime,
            allDay: false,
            id: data.id,
            color: data.color,
            userId: userIdInput.value,
            recurring: false,
          },
          "unavailabilities"
        );
      }

      if (modalDelete.style.display === "block") {
        removeEvent(parseInt(unavailabilityId.value), true);
      }

      calendar.unselect();
      unavailabilityModal.hide();
      calendar.refetchEvents();
    })
    .catch((error) => {
      console.log("An error occurred: " + error.message);
    });
};

const removeEvent = (id, bypass) => {
  const event = calendar.getEventById(id);

  if (
    (bypass ||
      confirm("Are you sure you want to delete this unavailability?")) &&
    event !== null
  ) {
    fetch("/staff_availabilities/" + id, {
      method: "DELETE",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ format: "json" }),
    })
      .then((response) => {
        if (response.ok) {
          event.remove();
        } else {
          console.log("An error occurred");
        }
        unavailabilityModal.hide();

        if (!bypass) {
          calendar.refetchEvents();
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
      staff_availability: {
        start_date: arg.event.start,
        end_date: arg.event.end,
      },
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
  modalTitle.innerText = "New Unavailability";
  modalDelete.style.display = "none";
  unavailabilityId.value = "";

  recurringInput.checked = true;
  dayInput.parentElement.style.display = "block";
  startDateInput.parentElement.parentElement.style.display = "none";
  endDateInput.parentElement.parentElement.style.display = "none";

  if (arg !== undefined && arg !== null) {
    startTimePicker.setDate(Date.parse(arg.startStr));
    startDatePicker.setDate(Date.parse(arg.startStr));
    endTimePicker.setDate(Date.parse(arg.endStr));
    endDatePicker.setDate(Date.parse(arg.endStr));
    dayInput.value = new Date(Date.parse(arg.startStr)).getDay();
  }

  unavailabilityModal.show();
};

const editModal = (arg) => {
  modalTitle.innerText = "Edit Unavailability";
  modalDelete.style.display = "block";

  if (arg !== undefined && arg !== null) {
    startTimePicker.setDate(Date.parse(arg.event.startStr));
    startDatePicker.setDate(Date.parse(arg.event.startStr));
    endTimePicker.setDate(Date.parse(arg.event.endStr));
    endDatePicker.setDate(Date.parse(arg.event.endStr));
    dayInput.value = new Date(Date.parse(arg.event.startStr)).getDay();

    unavailabilityId.value = arg.event.id;
    recurringInput.checked = arg.event.extendedProps.recurring;

    if (arg.event.extendedProps.recurring) {
      dayInput.parentElement.style.display = "block";
      startDateInput.parentElement.parentElement.style.display = "none";
      endDateInput.parentElement.parentElement.style.display = "none";
    } else {
      dayInput.parentElement.style.display = "none";
      startDateInput.parentElement.parentElement.style.display = "block";
      endDateInput.parentElement.parentElement.style.display = "block";
    }
  }

  unavailabilityModal.show();
};

modalDelete.addEventListener("click", () => {
  removeEvent(parseInt(unavailabilityId.value), false);
});
