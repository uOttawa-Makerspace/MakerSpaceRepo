import "flatpickr";
import { Calendar } from "@fullcalendar/core";
import "@fullcalendar/common/main.css";
import interactionPlugin from "@fullcalendar/interaction";
import timeGridPlugin from "@fullcalendar/timegrid";
import listPlugin from "@fullcalendar/list";
import TomSelect from "tom-select";
import { Modal } from "bootstrap";

// Modal
const unavailabilityModal = new Modal(
  document.getElementById("unavailabilityModal")
);

const modalTitle = document.getElementById("modal-title");
const modalDelete = document.getElementById("modal-delete");
const unavailabilityId = document.getElementById("unavailability-id");

// Inputs
const dayInput = document.getElementById("day");
const timePeriodIdInput = document.getElementById("time-period-id");
const startTimeInput = document.getElementById("start-time");
const startDateInput = document.getElementById("start-date");
const endTimeInput = document.getElementById("end-time");
const endDateInput = document.getElementById("end-date");
const recurringInput = document.getElementById("recurring");

let calendarEl = document.getElementById("user_availabilities_calendar");
const urlParams = new URLSearchParams(window.location.search);
const staff_id = urlParams.get("staff_id");
const time_period_id = urlParams.get("time_period_id");

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

let calendar = new Calendar(calendarEl, {
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
  slotMinTime: "07:00:00",
  slotMaxTime: "22:00:00",
  eventTimeFormat: {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  },
  editable: true,
  dayMaxEvents: true,
  slotEventOverlap: false,
  eventSources: [
    {
      id: "unavailabilities",
      url: `/staff_availabilities/get_availabilities?staff_id=${staff_id}${
        time_period_id ? "&time_period_id=" + time_period_id : ""
      }`,
    },
  ],
  // https://fullcalendar.io/docs/eventSourceSuccess
  // https://fullcalendar.io/docs/eventDataTransform
  eventDataTransform(eventData) {
    console.log(eventData);
    if (eventData.exception) {
      eventData.display = "none";
      console.log("excepted");
    } else {
      console.log("no exceptions");
    }
    return eventData;
  },
  select: function (arg) {
    openModal(arg);
  },
  eventClick: function (arg) {
    editModal(arg);
  },
  eventDrop: function (arg) {
    modifyEvent(arg);
  },
  eventResize: function (arg) {
    modifyEvent(arg);
  },
});
calendar.render();

let createEvent = () => {
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
            userId: data.userId,
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
            userId: data.userId,
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

let modifyEvent = (arg) => {
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

let removeEvent = (id, bypass) => {
  const event = calendar.getEventById(id);

  if (
    (bypass || confirm("Are you sure you want to delete this event?")) &&
    event !== null
  ) {
    fetch("/staff_availabilities/" + event.id, {
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
if (document.getElementById("staff_id")) {
  if (!document.getElementById("staff_id").tomselect) {
    new TomSelect("#staff_id", {
      maxItems: 1,
      placeholder: "Select Staff",
      maxOptions: null,
    });
  }
}

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

document
  .getElementById("modal-save")
  .addEventListener("click", () => createEvent());

modalDelete.addEventListener("click", () => {
  removeEvent(parseInt(unavailabilityId.value), false);
});
