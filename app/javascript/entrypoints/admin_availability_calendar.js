import "flatpickr";
import { Calendar } from "@fullcalendar/core";
//import "@fullcalendar/common/main.css";
import interactionPlugin from "@fullcalendar/interaction";
import timeGridPlugin from "@fullcalendar/timegrid";
import listPlugin from "@fullcalendar/list";
import { Modal, Toast } from "bootstrap";
import { Turbo } from "@hotwired/turbo-rails";

document.addEventListener("turbo:load", function () {
  const parseDateString = (dateString, endOfDay = false) => {
    const split = dateString.split("-");
    // Note: month is 0-based in JavaScript Date objects, so we subtract 1 from the month
    const year = parseInt(split[0], 10);
    const month = parseInt(split[1], 10) - 1;
    const day = parseInt(split[2], 10);

    if (endOfDay) {
      return new Date(year, month, day, 23, 59, 59, 999);
    } else {
      return new Date(year, month, day, 0, 0, 0, 0);
    }
  };

  // Modal
  const unavailabilityModal = new Modal(
    document.getElementById("unavailabilityModal"),
  );

  const modalTitle = document.getElementById("modal-title");
  const modalDelete = document.getElementById("modal-delete");
  const modalDeleteRecurring = document.getElementById(
    "modal-delete-recurring",
  );
  const modalDeleteRecThis = document.getElementById(
    "modal-delete-recurring-this-only",
  );
  const modalDeleteRecRest = document.getElementById(
    "modal-delete-recurring-this-and-rest",
  );
  const modalDeleteRecAll = document.getElementById(
    "modal-delete-recurring-all",
  );
  const unavailabilityId = document.getElementById("unavailability-id");

  const timePeriodStart = parseDateString(
    document.getElementById("time-period-start").value,
    false,
  );
  const timePeriodEnd = parseDateString(
    document.getElementById("time-period-end").value,
    true,
  );

  // Show state
  let showUnavailabilities = "block";
  let hiddenIds = {};
  const urlParams = new URLSearchParams(window.location.search);
  const time_period_id = urlParams.get("time_period_id");
  const timePeriodWarningContainer = document.getElementById(
    "time-period-warning-container",
  );

  // Inputs
  const dayInput = document.getElementById("day");
  const userIdInput = document.getElementById("user-id");
  const timePeriodIdInput = document.getElementById("time-period-id");
  const startTimeInput = document.getElementById("start-time");
  const startDateInput = document.getElementById("start-date");
  const endTimeInput = document.getElementById("end-time");
  const endDateInput = document.getElementById("end-date");
  const recurringInput = document.getElementById("recurring");
  const saveButton = document.getElementById("modal-save");
  const wholeDayCheckbox = document.getElementById("whole_day");
  const startTimeContainer = document.getElementById("start-time-container");
  const endTimeContainer = document.getElementById("end-time-container");
  const startDateContainer = document.getElementById("start-date-container");
  const endDateContainer = document.getElementById("end-date-container");

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

  let prevStartDate = timePeriodStart;
  let prevEndDate = timePeriodEnd;
  const switchInputVisibility = (recurring) => {
    if (recurring) {
      prevStartDate = startDateInput.value;
      prevEndDate = endDateInput.value;
      startDateInput.labels[0].textContent = "Repeat from...";
      endDateInput.labels[0].textContent = "...Until";
      startDatePicker.setDate(timePeriodStart);
      endDatePicker.setDate(timePeriodEnd);
    } else {
      startDateInput.labels[0].textContent = "Start Date";
      endDateInput.labels[0].textContent = "End Date";
      startDatePicker.setDate(prevStartDate);
      endDatePicker.setDate(prevEndDate);
    }
    // Recurring input
    modalDeleteRecurring.style.display = recurring ? "block" : "none";
    modalDelete.style.display = recurring ? "none" : "block";
  };

  recurringInput.addEventListener("change", function () {
    switchInputVisibility(recurringInput.checked);
  });

  recurringInput.addEventListener("change", checkDate);

  // Disable time fields if block is whole day
  wholeDayCheckbox.addEventListener("change", function () {
    if (this.checked) {
      startTimeInput.setAttribute("disabled", "");
      endTimeInput.setAttribute("disabled", "");
    } else {
      startTimeInput.removeAttribute("disabled");
      endTimeInput.removeAttribute("disabled");
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

  function checkDate() {
    if (recurringInput.checked) {
      timePeriodWarningContainer.style.display = "none";
      saveButton.disabled = false;
    } else {
      const selectedStartDate = new Date(startDateInput.value);
      const selectedEndDate = new Date(endDateInput.value);

      const startTimeZoneOffsetMinutes = selectedStartDate.getTimezoneOffset();
      const endTimeZoneOffsetMinutes = selectedEndDate.getTimezoneOffset();

      const adjustedStartDate = new Date(
        selectedStartDate.getTime() + startTimeZoneOffsetMinutes * 60000,
      );
      const adjustedEndDate = new Date(
        selectedEndDate.getTime() + endTimeZoneOffsetMinutes * 60000,
      );

      let startDateInRange = true;
      let endDateInRange = true;

      if (
        adjustedStartDate < timePeriodStart ||
        adjustedStartDate > timePeriodEnd
      ) {
        startDateInRange = false;
      }
      if (
        adjustedEndDate < timePeriodStart ||
        adjustedEndDate > timePeriodEnd
      ) {
        endDateInRange = false;
      }

      if (!startDateInRange || !endDateInRange) {
        timePeriodWarningContainer.style.display = "block";
        saveButton.disabled = true;
      } else {
        timePeriodWarningContainer.style.display = "none";
        saveButton.disabled = false;
      }
    }
  }

  startDateInput.addEventListener("change", checkDate);
  endDateInput.addEventListener("change", checkDate);

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
    eventStartEditable: false,
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
    dayCellDidMount: function (info) {
      const originalDate = info.date;
      const timeZoneOffsetMinutes = originalDate.getTimezoneOffset();
      const adjustedDate = new Date(
        originalDate.getTime() + timeZoneOffsetMinutes * 60000,
      );

      // gray out days that are not in the range of the time period
      if (adjustedDate < timePeriodStart || adjustedDate > timePeriodEnd) {
        info.el.style.backgroundColor = "#CCCCCC";
      }
    },
    select: (arg) => {
      if (arg.start >= timePeriodStart && arg.start <= timePeriodEnd) {
        openModal(arg);
      } else {
        alert("This date is outside of the time period");
        calendar.unselect();
      }
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
    // HACK this thing is a disaster
    // Fullcalendar uses absolute positioning with precomputed dimensions
    // so hiding the topmost element with css still leaves the gap
    // https://stackoverflow.com/q/65414252
    // The only proper way to hide an event seems to be to set the display property but we use that for applying event exceptions.
    // So we add a second marker class called 'event-excepted' to tell the visibility checkboxes to leave the event display alone
    // TODO: Make the server implement the exceptions, instead of having clients interpret and render them. That would be an actual fix
    // NOTE: This runs for each event. Recurring and single-day events are separate data objects. This event targets recurring events
    // Recurring objects mean they recur on the same day of the week, between a start and end date. Used for putting in your class schedule
    // This runs on every event data fetch, so when we change the active view start and end date, it triggers an event refetch
    eventDataTransform(eventData) {
      eventData.start_date = eventData.startRecur;
      eventData.end_date = eventData.endRecur;
      // Place defaut value
      eventData.display = "block";
      eventData.eventExcepted = false;
      if (
        showUnavailabilities == "none" ||
        hiddenIds[eventData.userId] == "none"
      ) {
        eventData.display = "none";
      }
      // Exceptions come in
      if (eventData.exceptions && eventData.exceptions.length > 0) {
        // For each exception
        for (let { covers, start_at } of eventData.exceptions) {
          // One time and today is the day
          // look at the time component of it only
          if (
            covers == "one_time" &&
            new Date(start_at).getTime() === calendar.view.activeStart.getTime()
          ) {
            eventData.eventExcepted = true;
            eventData.display = "none";
          }
          // All after the start day
          if (
            covers == "all_after" &&
            new Date(start_at) <= calendar.view.activeStart
          ) {
            eventData.eventExcepted = true;
            eventData.display = "none";
          }
        }
      }

      return eventData;
    },
  });

  calendar.render();

  // Hide/Show Events
  const hideShowEvents = (event, eventName) => {
    //calendar.refetchEvents();
    // Update UI buttons
    if (eventName === "unavailabilities") {
      [...document.getElementsByClassName("shift-hide-button")].forEach(
        (el) => {
          let id = el.id.split("-")[1];
          if (!(hiddenIds[id] === "none")) {
            el.checked = showUnavailabilities === "block";
          }
          // showUnavailabilities = document.getElementById(
          //   "hide-show-unavailabilities"
          // ).checked
          //   ? "block"
          //   : "none";
        },
      );
    } /*else if (eventName === "id") {
        document.querySelectorAll(`[data-user-id="${event}"]`).forEach((el) => {
        el.checked = hiddenIds[event] === "block";
        });
        }*/
    if (eventName === "check") {
      for (let e of calendar.getEvents()) {
        //e.setProp("display", showUnavailabilities);
      }
    }
  };

  // Hide/Show all unavailabilities toggle
  document
    .getElementById("hide-show-unavailabilities")
    .addEventListener("change", (total) => {
      document.querySelectorAll(".shift-hide-button").forEach((i) => {
        i.checked = total.target.checked;
        toggleVisibility(i.dataset.userId, false);
      });
      // HACK to trigger render
      calendar.getEvents()[0].setExtendedProp("", "");
    });

  // Hide/Show unavailabilities for a single staff
  window.toggleVisibility = (id, rerender = true) => {
    hiddenIds[id] = document.getElementById(`user-${id}`).checked
      ? "block"
      : "none";
    // Find all events with user id (and not excepted)
    calendar.getEvents().forEach((ev) => {
      if (ev.extendedProps.userId == id && !ev.extendedProps.eventExcepted) {
        // this triggers a render, and there are around a hundred event per week
        //ev.setProp('display', hiddenIds[id])
        // so this slows down the loop. Not sure if this is fixable without editing library source
        // HACK set the internal property directly. Good luck if you upgrade the library lol
        ev._def.ui.display = hiddenIds[id];
      }
    });
    // then trigger a 'property update' to rerender
    if (rerender) {
      calendar.getEvents()[0].setExtendedProp("", "");
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
          //Turbo.visit(window.location, { action: "replace" });
          calendar.refetchEvents();
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
  const createCalendarEvent = (exceptionType) => {
    let eventId = parseInt(unavailabilityId.value) || undefined;
    fetch(`/staff_availabilities/${eventId || ""}`, {
      method: eventId ? "PUT" : "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        staff_availability: {
          day: dayInput.value,
          time_period_id: timePeriodIdInput.value,
          // If whole day, put in 00:00
          start_time: wholeDayCheckbox.checked ? "00:00" : startTimeInput.value,
          start_date: startDateInput.value,
          end_time: wholeDayCheckbox.checked ? "23:59" : endTimeInput.value,
          // If checked, don't span multiple days - keep the start day only
          end_date: wholeDayCheckbox.checked
            ? startDateInput.value
            : endDateInput.value,
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
        staff_id: userIdInput.value,
        format: "json",
      }),
    })
      .then((response) => response.json())
      .then((data) => {
        calendar.addEvent(
          {
            title: data.title,
            start: data.startTime,
            end: data.endTime,
            startTime: data.startTime,
            endTime: data.endTime,
            daysOfWeek: data.daysOfWeek,
            allDay: false,
            id: data.id,
            color: data.color,
            userId: userIdInput.value,
            recurring: data.recurring,
            startRecur: data.timePeriodStart,
            endRecur: data.timePeriodEnd,
          },
          "unavailabilities",
        );

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
  saveButton.addEventListener("click", () => createCalendarEvent());

  // Open modal with right values inside
  const openModal = (arg) => {
    // Reset defaults
    modalTitle.innerText = "New Unavailability";
    recurringInput.checked = true;
    wholeDayCheckbox.checked = false; // Reset checkbox state
    unavailabilityId.value = "";

    // Set default visibility based on whether the event is recurring or whole day
    if (arg !== undefined && arg !== null) {
      startTimePicker.setDate(Date.parse(arg.startStr));
      startDatePicker.setDate(Date.parse(arg.startStr));
      //startDatePicker.clear();
      endTimePicker.setDate(Date.parse(arg.endStr));
      endDatePicker.setDate(Date.parse(arg.endStr));
      //endDatePicker.clear();
      dayInput.value = new Date(Date.parse(arg.startStr)).getDay();
      wholeDayCheckbox.checked =
        new Date(Date.parse(arg.endStr)).getHours() === 23 &&
        new Date(Date.parse(arg.endStr)).getMinutes() === 59;
    }

    // Toggle recurring, and save start and end dates
    switchInputVisibility(recurringInput.checked);
    // But that function shows the delete button, so we use the html hidden attribute as an override
    modalDelete.hidden = true;
    modalDeleteRecurring.hidden = true;

    // Apply the whole day settings if needed
    wholeDayCheckbox.dispatchEvent(new Event("change"));

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
      userIdInput.value = arg.event.extendedProps.userId;

      switchInputVisibility(arg.event.extendedProps.recurring);

      let eventStart = new Date(Date.parse(arg.event.startStr));
      let eventEnd = new Date(Date.parse(arg.event.endStr));
      wholeDayCheckbox.checked =
        eventStart.getHours() === 0 &&
        eventStart.getMinutes() === 0 &&
        eventEnd.getHours() === 23 &&
        eventEnd.getMinutes() === 59;

      recurringInput.dispatchEvent(new Event("change"));
      wholeDayCheckbox.dispatchEvent(new Event("change"));
    }

    modalDelete.hidden = false;
    modalDeleteRecurring.hidden = false;

    unavailabilityModal.show();
  };

  // Delete the entire event
  modalDelete.addEventListener("click", () => {
    removeEvent(parseInt(unavailabilityId.value), false);
  });
  // Delete options for recurring events
  modalDeleteRecThis.addEventListener("click", () =>
    createCalendarEvent("one_time"),
  );
  modalDeleteRecRest.addEventListener("click", () =>
    createCalendarEvent("all_after"),
  );
  modalDeleteRecAll.addEventListener("click", () =>
    removeEvent(parseInt(unavailabilityId.value), false),
  );
});
