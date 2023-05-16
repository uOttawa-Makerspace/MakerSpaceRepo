import { Calendar } from "@fullcalendar/core";
import "@fullcalendar/common/main.css";
import interactionPlugin from "@fullcalendar/interaction";
import timeGridPlugin from "@fullcalendar/timegrid";
import listPlugin from "@fullcalendar/list";
import googleCalendarPlugin from "@fullcalendar/google-calendar";
import { Turbo } from "@hotwired/turbo-rails";
import iCalendarPlugin from "@fullcalendar/icalendar";
import { Modal, Toast } from "bootstrap";
import TomSelect from "tom-select";

// Time slot constants
const SLOT_MIN_TIME = new Date(new Date().setHours(7, 0, 0, 0));
const SLOT_MAX_TIME = new Date(new Date().setHours(23, 0, 0, 0));

// Modal
const shiftModal = new Modal(document.getElementById("shiftModal"));

// Show
let sourceShow = {
  google: document.getElementById("hide-show-google-events").checked
    ? "block"
    : "none",
  transparent: document.getElementById("hide-show-unavailabilities").checked
    ? "block"
    : "none",
  staffNeeded: document.getElementById("hide-show-staff-needed").checked
    ? "block"
    : "none",
};
let hiddenIds = {};
const urlParams = new URLSearchParams(window.location.search);
const time_period_id = urlParams.get("time_period_id");

// Inputs
const startDateTimeInput = document.getElementById("start-datetime");
const endDateTimeInput = document.getElementById("end-datetime");
const userIdInput = document.getElementById("user-id");
const reasonInput = document.getElementById("reason");
const trainingIdInput = document.getElementById("training_id");
const levelInput = document.getElementById("level");
const courseInput = document.getElementById("course");
const modalSave = document.getElementById("modal-save");

const modalDelete = document.getElementById("modal-delete");
const modalClose = document.getElementById("modal-close");
modalClose.addEventListener("click", () => {
  if (modalDelete.classList.contains("d-block")) {
    modalDelete.classList.remove("d-block");
    modalDelete.classList.add("d-none");
  }
});

modalSave.addEventListener("click", () => {
  createCalendarEvent();
});

modalDelete.addEventListener("click", () => {
  removeEvent(document.getElementById("shift-id").value, null);
});

const startPicker = startDateTimeInput.flatpickr({
  enableTime: true,
  time_24hr: true,
  altInput: true,
  altFormat: "F j, Y at H:i",
  onChange: (selectedDates, dateStr, instance) => {
    let selectedItems = [...userIdInput.tomselect.items];
    populateUsers({
      start: new Date(
        Date.parse(selectedDates[0]) -
          new Date().getTimezoneOffset() * 60 * 1000
      ),
      end: new Date(
        Date.parse(endPicker.selectedDates[0]) -
          new Date().getTimezoneOffset() * 60 * 1000
      ),
    }).then(() => {
      for (let id of selectedItems) {
        userIdInput.tomselect.addItem(id);
      }
    });
  },
});

const endPicker = endDateTimeInput.flatpickr({
  enableTime: true,
  time_24hr: true,
  altInput: true,
  altFormat: "F j, Y at H:i",
  onChange: (selectedDates, dateStr, instance) => {
    let selectedItems = [...userIdInput.tomselect.items];
    populateUsers({
      end: new Date(
        Date.parse(selectedDates[0]) -
          new Date().getTimezoneOffset() * 60 * 1000
      ),
      start: new Date(
        Date.parse(startPicker.selectedDates[0]) -
          new Date().getTimezoneOffset() * 60 * 1000
      ),
    }).then(() => {
      for (let id of selectedItems) {
        userIdInput.tomselect.addItem(id);
      }
    });
  },
});

new TomSelect("#user-id", {
  maxItems: null,
  placeholder: "Select users",
  search: true,
  plugins: ["remove_button"],
});

let events = 0;
// Calendar Config
let calendarEl = document.getElementById("calendar");

let calendar;

document.addEventListener("turbo:load", () => {
  calendarEl.remove();
  calendarEl = document.createElement("div");
  calendarEl.id = "calendar";
  document.getElementById("calendar-container").appendChild(calendarEl);
  events = 0;

  fetch("/admin/shifts/get_external_staff_needed", {
    method: "GET",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
  })
    .then((res) => res.json())
    .then((res) => {
      calendar = new Calendar(calendarEl, {
        plugins: [
          interactionPlugin,
          timeGridPlugin,
          listPlugin,
          googleCalendarPlugin,
          iCalendarPlugin,
        ],
        customButtons: {
          addNewEvent: {
            text: "+",
            click: () => {
              openModal();
            },
          },
          copyToNextWeek: {
            text: "Copy to next week",
            click: () => {
              copyToNextWeek();
            },
          },
        },
        headerToolbar: {
          left: "prev,today,next",
          center: "copyToNextWeek",
          right: "addNewEvent,timeGridWeek,timeGridDay",
        },
        contentHeight: "auto",
        slotEventOverlap: false,
        allDaySlot: false,
        timeZone: "America/New_York",
        initialView: "timeGridWeek",
        navLinks: true,
        selectable: true,
        selectMirror: true,
        slotMinTime: SLOT_MIN_TIME.toTimeString().split(" ")[0],
        slotMaxTime: SLOT_MAX_TIME.toTimeString().split(" ")[0],
        eventTimeFormat: {
          hour: "2-digit",
          minute: "2-digit",
          hour12: false,
        },
        editable: true,
        dayMaxEvents: true,
        eventSources: [
          {
            id: "transparent",
            url: `/admin/shifts/get_availabilities?transparent=true${
              time_period_id ? "&time_period_id=" + time_period_id : ""
            }`,
            editable: false,
          },
          {
            id: "shifts",
            url: "/admin/shifts/get_shifts",
          },
          {
            id: "google",
            googleCalendarApiKey: "AIzaSyCMNxnP0pdKHtZaPBJAtfv68A2h6qUeuW0",
            googleCalendarId:
              "c_d7liojb08eadntvnbfa5na9j98@group.calendar.google.com",
            color: "rgba(255,31,31,0.4)",
            editable: false,
          },
          {
            id: "staffNeeded",
            url: "/admin/shifts/get_staff_needed",
            color: "rgba(40,40,40,0.4)",
            editable: false,
          },
          ...res.map((cal) => {
            return {
              id: "staffNeeded",
              color: cal.color,
              editable: false,
              ...(cal.calendar_url.includes(".ics")
                ? {
                    format: "ics",
                    url: `/admin/shifts/ics?staff_needed_calendar_id=${cal.id}`,
                  }
                : {
                    googleCalendarApiKey:
                      "AIzaSyCMNxnP0pdKHtZaPBJAtfv68A2h6qUeuW0",
                    googleCalendarId: cal.calendar_url,
                  }),
            };
          }),
        ],
        select: (arg) => {
          openModal(arg);
        },
        eventClick: (arg) => {
          if (arg.event.source.id === "shifts") {
            editShift(arg);
          } else if (arg.event.source.id === "staffNeeded") {
            staffNeededEvent(arg);
          }
        },
        eventDrop: (arg) => {
          let shiftStartHour = new Date(
            Date.parse(arg.event.start.toString()) +
              new Date().getTimezoneOffset() * 60 * 1000
          ).getHours();
          let shiftEndHour = new Date(
            Date.parse(arg.event.end.toString()) +
              new Date().getTimezoneOffset() * 60 * 1000
          ).getHours();
          if (
            shiftStartHour < SLOT_MIN_TIME.getHours() ||
            shiftEndHour > SLOT_MAX_TIME.getHours() ||
            (shiftEndHour >= 0 && shiftEndHour < shiftStartHour)
          ) {
            arg.revert();
            return;
          }
          modifyEvent(arg);
        },
        eventResize: (arg) => {
          modifyEvent(arg);
        },
        eventOrder: (a, b) => {
          if (
            (a.title.includes("is unavailable") &&
              b.title.includes("is unavailable")) ||
            (!a.title.includes("is unavailable") &&
              !b.title.includes("is unavailable"))
          ) {
            return 0;
          } else if (a.title.includes("is unavailable")) {
            return -1;
          } else {
            return 1;
          }
        },
        eventSourceSuccess: (content, xhr) => {
          content.forEach((event) => {
            if (hiddenIds[event.userId] === "none") {
              event.display = "none";
            } else if (hiddenIds[event.userId] === "block") {
              event.display = "block";
            } else {
            }
          });
          hideShowEvents("check");
          return content;
        },
      });
      calendar.render();
      document.getElementById("hide-show-unavailabilities").click();
    });
});

// Refresh pending Shifts
const refreshPendingShifts = () => {
  fetch("/admin/shifts/pending_shifts?format=js", {
    method: "GET",
  })
    .then((r) => r.text())
    .then((html) => {
      const fragment = document.createRange().createContextualFragment(html);
      document
        .getElementById("pending-shift-partial")
        .replaceChildren(fragment);
    });
};

const populateUsers = (arg) => {
  return new Promise((resolve, reject) => {
    userIdInput.tomselect.clear();
    userIdInput.tomselect.clearOptions();
    let startDate, endDate;
    if (arg.event) {
      startDate = arg.event.start;
      endDate = arg.event.end;
    } else {
      startDate = arg.start;
      endDate = arg.end;
    }
    let startHour = startDate.toUTCString().split(" ")[4].split(":")[0];
    let startMinute = startDate.toUTCString().split(" ")[4].split(":")[1];
    let endHour = endDate.toUTCString().split(" ")[4].split(":")[0];
    let endMinute = endDate.toUTCString().split(" ")[4].split(":")[1];
    let weekDayInt = {
      "Sun,": 0,
      "Mon,": 1,
      "Tue,": 2,
      "Wed,": 3,
      "Thu,": 4,
      "Fri,": 5,
      "Sat,": 6,
    }[startDate.toUTCString().split(" ")[0]];
    fetch(
      `/admin/shifts/shift_suggestions?start=${startHour}:${startMinute}&end=${endHour}:${endMinute}&day=${weekDayInt}`,
      {
        method: "GET",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
        },
      }
    )
      .then((res) => res.json())
      .then((res) => {
        res.forEach((user) => {
          userIdInput.tomselect.addOption({
            value: user.id,
            text: `${user.name} ${user.acceptable ? "" : "(unavailable)"}`,
          });
        });
        resolve();
      })
      .catch((err) => {
        reject(err);
      });
  });
};

// Calendar CRUD
const createCalendarEvent = () => {
  modalSave.disabled = true;
  modalSave.querySelector("span").classList.remove("d-none");
  let selected_users = [];
  for (let option of userIdInput.options) {
    if (option.selected) {
      selected_users.push(option.value);
    }
  }
  fetch("/admin/shifts", {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      start_datetime: startDateTimeInput.value,
      end_datetime: endDateTimeInput.value,
      format: "json",
      user_id: selected_users,
      reason: reasonInput.value,
      ...(reasonInput.value === "Training" && {
        training_id: trainingIdInput.value,
        level: levelInput.value,
        course: courseInput.value,
      }),
    }),
  })
    .then((response) => response.json())
    .then((data) => {
      if (data.error) {
        const toast = new Toast(
          document.getElementById("toast-color-shift-failed")
        );
        toast.show();
      } else {
        calendar.addEvent(
          {
            title: data.name,
            start: data.start,
            end: data.end,
            allDay: false,
            id: data["id"],
            color: data.color,
            className: data.className,
          },
          "shifts"
        );
        shiftModal.hide();
        calendar.unselect();
        refreshPendingShifts();
        if (modalDelete.classList.contains("d-block")) {
          removeEvent(document.getElementById("shift-id").value, true);
        }
      }
    })
    .catch((error) => {
      console.log("An error occurred: " + error.message);
    });
  modalSave.disabled = false;
  modalSave.querySelector("span").classList.add("d-none");
};

const copyToNextWeek = () => {
  fetch("/admin/shifts/copy_to_next_week", {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      end_of_week: calendar.currentData.dateProfile.currentRange.end,
    }),
  }).then((response) => {
    if (response.ok) {
      calendar.refetchEvents();
      calendar.gotoDate(
        new Date(
          calendar.currentData.dateProfile.currentRange.end.getTime() +
            1000 * 60 * 60 * 24
        )
      );
    }
  });
};

const openModal = (arg) => {
  if (!arg) {
    arg = { start: new Date(), end: new Date() };
  }
  if (arg !== undefined && arg !== null) {
    startPicker.setDate(Date.parse(arg.startStr));
    endPicker.setDate(Date.parse(arg.endStr));
  }
  if (arg.event) {
    if (arg.event.source.id === "shifts") {
      document.getElementById("shift-id").value = arg.event.id;
    }
  }
  populateUsers(arg).then(() => {
    shiftModal.show();
  });
};
const modifyEvent = (arg) => {
  fetch("/admin/shifts/" + arg.event.id, {
    method: "PUT",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      start_datetime: new Date(
        Date.parse(arg.event.start.toString()) +
          new Date().getTimezoneOffset() * 60 * 1000
      ),
      end_datetime: new Date(
        Date.parse(arg.event.end.toString()) +
          new Date().getTimezoneOffset() * 60 * 1000
      ),
      ...(reasonInput.value === "Training" && {
        training_id: trainingIdInput.value,
        level: levelInput.value,
        course: courseInput.value,
      }),
      format: "json",
    }),
  })
    .then((response) => {
      if (!response.ok) {
        arg.revert();
      }
      refreshPendingShifts();
    })
    .catch((error) => {
      console.log("An error occurred: " + error.message);
    });
};
const removeEvent = (shift_id, bypass = false) => {
  let confirmation = bypass
    ? true
    : confirm("Are you sure you want to delete this shift?");
  if (confirmation) {
    fetch("/admin/shifts/" + shift_id, {
      method: "DELETE",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ format: "json" }),
    })
      .then((response) => {
        if (response.ok) {
          calendar.refetchEvents();
          refreshPendingShifts();
          shiftModal.hide();
          document.getElementById("shift-id").value = "";
          modalDelete.classList.remove("d-block");
          modalDelete.classList.add("d-none");
        } else {
          console.log("An error occurred");
        }
        refreshPendingShifts();
      })
      .catch((error) => {
        console.log("An error occurred: " + error.message);
      });
  }
};

const editShift = (arg) => {
  document.getElementById("shift-id").value = arg.event.id;
  modalDelete.classList.remove("d-none");
  modalDelete.classList.add("d-block");
  fetch("/admin/shifts/get_shift?id=" + arg.event.id, {
    method: "GET",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
  })
    .then((response) => response.json())
    .then((data) => {
      startPicker.setDate(Date.parse(data.start_datetime));
      endPicker.setDate(Date.parse(data.end_datetime));
      reasonInput.value = data.reason;

      if (data.reason === "Training") {
        trainingIdInput.value = data.training_id;
        levelInput.value = data.level;
        courseInput.value = data.course;

        const trainingContainer = document.getElementById("training-container");
        trainingContainer.classList.remove("d-none");
        trainingContainer.classList.add("d-block");
      }

      populateUsers({
        start: new Date(
          Date.parse(data.start_datetime) +
            new Date().getTimezoneOffset() * 60 * 1000
        ),
        end: new Date(
          Date.parse(data.end_datetime) +
            new Date().getTimezoneOffset() * 60 * 1000
        ),
      }).then(() => {
        data.users.forEach((user) => {
          userIdInput.tomselect.addItem(user.id);
        });
      });
      shiftModal.show();
    });
};

const staffNeededEvent = (arg) => {
  openModal(arg);
  startPicker.setDate(
    Date.parse(arg.event.start) + new Date().getTimezoneOffset() * 60 * 1000
  );
  endPicker.setDate(
    Date.parse(arg.event.end) + new Date().getTimezoneOffset() * 60 * 1000
  );
};

// Hide/Show Events
const hideShowEvents = (eventName) => {
  eventName === "check" ? (events += 1) : events;

  if (events >= Object.keys(calendar.currentData.eventSources).length) {
    document.getElementById("spinner").classList.add("d-none");
  }

  let allEvents = calendar.getEvents();
  if (eventName !== "check") {
    sourceShow[eventName] = sourceShow[eventName] === "none" ? "block" : "none";
  }

  let eventsToProcess = [];
  if (eventName === "check") {
    eventsToProcess = allEvents.filter((ev) =>
      sourceShow.hasOwnProperty(ev.source.id)
    );
  } else {
    eventsToProcess = allEvents.filter((ev) => ev.source.id === eventName);
  }

  calendar.batchRendering(() => {
    for (let ev of eventsToProcess) {
      let display = sourceShow[ev.source.id] || "block";
      ev.setProp(
        "display",
        hiddenIds[ev.extendedProps.userId] === "none" ? "none" : display
      );
    }
  });

  if (eventName === "transparent") {
    [...document.getElementsByClassName("shift-hide-button")].forEach((el) => {
      let userId = el.id.substring(5);
      el.checked =
        hiddenIds[userId] === "none"
          ? false
          : sourceShow["transparent"] === "block";
    });
  }
};

document
  .getElementById("hide-show-unavailabilities")
  .addEventListener("click", () => {
    hideShowEvents("transparent");
  });

document
  .getElementById("hide-show-google-events")
  .addEventListener("click", () => {
    hideShowEvents("google");
  });

document
  .getElementById("hide-show-staff-needed")
  .addEventListener("click", () => {
    hideShowEvents("staffNeeded");
  });

document.getElementById("reason").addEventListener("change", (el) => {
  const trainingContainer = document.getElementById("training-container");
  if (el.target.value === "Training") {
    trainingContainer.classList.remove("d-none");
    trainingContainer.classList.add("d-block");
  } else {
    trainingContainer.classList.remove("d-block");
    trainingContainer.classList.add("d-none");
  }
});

// Toggle Staff Visibility
window.toggleVisibility = (id) => {
  let allEvents = calendar.getEvents();
  for (let ev of allEvents) {
    if (ev.extendedProps.userId === id) {
      ev.setProp(
        "display",
        document.getElementById(`user-${id}`).checked ? "block" : "none"
      );
      hiddenIds[id] = document.getElementById(`user-${id}`).checked
        ? "block"
        : "none";
    }
  }
};

// Update the staff's color
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
        const toast = new Toast(
          document.getElementById("toast-color-update-failed")
        );
        toast.show();
      }
    })
    .catch((error) => {
      const toast = new Toast(
        document.getElementById("toast-color-update-failed")
      );
      toast.show();
      console.log("An error occurred: " + error.message);
    });
};
