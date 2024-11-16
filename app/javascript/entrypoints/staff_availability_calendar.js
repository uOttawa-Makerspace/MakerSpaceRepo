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
const modalDeleteRecurring = document.getElementById("modal-delete-recurring");
const modalDeleteRecThis = document.getElementById(
  "modal-delete-recurring-this-only"
);
const modalDeleteRecRest = document.getElementById(
  "modal-delete-recurring-this-and-rest"
);
const modalDeleteRecAll = document.getElementById("modal-delete-recurring-all");
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

const switchInputVisibility = (recurring) => {
  modalDeleteRecurring.style.display = recurring ? "block" : "none";
  modalDelete.style.display = recurring ? "none" : "block";
};

recurringInput.addEventListener("change", function () {
  // this.checked == true if recurring
  switchInputVisibility(this.checked);
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
    // Because fullcalendar doesn't expose these variables
    // we keep them for later
    eventData.start_date = eventData.startRecur;
    eventData.end_date = eventData.endRecur;
    if (eventData.exceptions && eventData.exceptions.length > 0) {
      for (let { covers, start_at } of eventData.exceptions) {
        // One time and today is the day
        if (
          covers == "one_time" &&
          new Date(start_at).getTime() === calendar.view.activeStart.getTime()
        ) {
          eventData.display = "none";
        }
        // All after the start day
        if (
          covers == "all_after" &&
          new Date(start_at) <= calendar.view.activeStart
        ) {
          eventData.display = "none";
        }
      }
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

let createEvent = (exceptionType) => {
  let eventId = parseInt(unavailabilityId.value) || undefined;
  fetch(`/staff_availabilities/${eventId || ""}`, {
    // If an ID exists we're editing not creating
    method: eventId ? "PUT" : "POST",
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
        // undefined values are not stringified
        exceptions_attributes: exceptionType && {
          0: {
            // Make sure this doesn't have an ID to have it appended
            covers: exceptionType,
            start_at: calendar.view.activeStart, // Send first day of week
          },
        },
      },
      format: "json",
    }),
  })
    .then((response) => response.json())
    .then((data) => {
      calendar.addEvent(
        {
          title: data.title,
          start: data.start,
          end: data.end,
          startTime: data.startTime,
          endTime: data.endTime,
          daysOfWeek: data.daysOfWeek,
          allDay: false,
          id: data.id,
          color: data.color,
          userId: data.userId,
          recurring: data.recurring,
          startRecur: data.timePeriodStart,
          endRecur: data.timePeriodEnd,
        },
        "unavailabilities"
      );

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
  modalDeleteRecurring.style.display = "none";
  unavailabilityId.value = "";

  recurringInput.checked = true;
  switchInputVisibility(recurringInput.checked);

  if (arg !== undefined && arg !== null) {
    startTimePicker.setDate(Date.parse(arg.startStr));
    //startDatePicker.setDate(Date.parse(arg.startStr));
    startDatePicker.clear();
    endTimePicker.setDate(Date.parse(arg.endStr));
    //endDatePicker.setDate(Date.parse(arg.endStr));
    endDatePicker.clear();
    dayInput.value = new Date(Date.parse(arg.startStr)).getDay();
  }

  unavailabilityModal.show();
};

const editModal = (arg) => {
  modalTitle.innerText = "Edit Unavailability";

  if (arg !== undefined && arg !== null) {
    startTimePicker.setDate(Date.parse(arg.event.startStr));
    startDatePicker.setDate(Date.parse(arg.event.extendedProps.start_date));
    endTimePicker.setDate(Date.parse(arg.event.endStr));
    endDatePicker.setDate(Date.parse(arg.event.extendedProps.end_date));
    dayInput.value = new Date(Date.parse(arg.event.startStr)).getDay();

    unavailabilityId.value = arg.event.id;
    recurringInput.checked = arg.event.extendedProps.recurring;

    switchInputVisibility(arg.event.extendedProps.recurring);
  }

  unavailabilityModal.show();
};

document
  .getElementById("modal-save")
  .addEventListener("click", () => createEvent());

modalDeleteRecThis.addEventListener("click", () => createEvent("one_time"));
modalDeleteRecRest.addEventListener("click", () => createEvent("all_after"));
modalDeleteRecAll.addEventListener("click", () =>
  removeEvent(parseInt(unavailabilityId.value), false)
);

modalDelete.addEventListener("click", () => {
  removeEvent(parseInt(unavailabilityId.value), false);
});
