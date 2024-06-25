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
const monthsToInt = {
  Jan: 1,
  Feb: 2,
  Mar: 3,
  Apr: 4,
  May: 5,
  Jun: 6,
  Jul: 7,
  Aug: 8,
  Sep: 9,
  Oct: 10,
  Nov: 11,
  Dec: 12,
};
const dayToInt = {
  "Sun,": 0,
  "Mon,": 1,
  "Tue,": 2,
  "Wed,": 3,
  "Thu,": 4,
  "Fri,": 5,
  "Sat,": 6,
};

// Modal
const shiftModal = new Modal(document.getElementById("shiftModal"));
const pendingShiftsModal = new Modal(document.getElementById("pendingShiftsModal"));

function makeModalDraggable(shiftModal) {
  const header = shiftModal.querySelector(".modal-header");

  let isDragging = false;
  let offsetX, offsetY;

  header.addEventListener("mousedown", function (e) {
    isDragging = true;
    offsetX = e.clientX - shiftModal.getBoundingClientRect().left;
    offsetY = e.clientY - shiftModal.getBoundingClientRect().top;
  });

  document.addEventListener("mousemove", function (e) {
    if (isDragging) {
      shiftModal.style.position = "absolute";
      shiftModal.style.left = e.clientX - offsetX + "px";
      shiftModal.style.top = e.clientY - offsetY + "px";
    }
  });

  document.addEventListener("mouseup", function () {
    isDragging = false;
  });

  shiftModal.addEventListener("hidden.bs.modal", function () {
    shiftModal.style.position = "";
    shiftModal.style.left = "";
    shiftModal.style.top = "";
  });
}

document.addEventListener("DOMContentLoaded", function () {
  const modalDOMElement = document.getElementById("shiftModal");
  if (modalDOMElement) {
    makeModalDraggable(modalDOMElement);
  }
});

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
const languageInput = document.getElementById("language");
const courseInput = document.getElementById("course");
const modalSave = document.getElementById("modal-save");
const trainingContainer = document.getElementById("training-container");

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
          confirmCurrentWeek: {
            text: "Confirm current week's shifts",
            click: () => {
              confirmCurrentWeekShifts();
            },
          },
        },
        headerToolbar: {
          left: "prev,today,next",
          center: "copyToNextWeek,confirmCurrentWeek",
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
        eventContent: (arg) => {
          const props = arg.event.extendedProps;
          let trainingStr = "";

          if (props.reason === "Training") {
            trainingStr = `<br> ${props.training ? props.training : ""} <br> ${
              props.language ? props.language : ""
            } <br> ${props.course ? props.course : ""}`;
          }

          return {
            html:
              '<div class="fc-event-main-frame"><div class="fc-event-time">' +
              arg.timeText +
              '</div><div class="fc-event-title-container"><div class="fc-event-title fc-sticky">' +
              arg.event.title +
              trainingStr +
              "</div></div></div>",
          };
        },
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
        datesSet: () => updateHours(),
        eventDidMount: (info) => {
          if (info.event.extendedProps.color) {
            info.el.style.background = info.event.extendedProps.color;
            info.el.style.borderColor = "transparent";
          }
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

      updateHours();
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
    let startSplit = startDate.toUTCString().split(" ");
    let endSplit = endDate.toUTCString().split(" ");

    let startYear = startSplit[3];
    let startMonth = monthsToInt[startSplit[2]];
    let startDay = startSplit[1];
    let startHour = startSplit[4].split(":")[0];
    let startMinute = startSplit[4].split(":")[1];

    let endYear = endSplit[3];
    let endMonth = monthsToInt[endSplit[2]];
    let endDay = endSplit[1];
    let endHour = endSplit[4].split(":")[0];
    let endMinute = endSplit[4].split(":")[1];

    let weekDayInt = dayToInt[startSplit[0]];

    let startDateTime = `${startYear}-${startMonth}-${startDay} ${startHour}:${startMinute}`;
    let endDateTime = `${endYear}-${endMonth}-${endDay} ${endHour}:${endMinute}`;
    let searchUrl = `/admin/shifts/shift_suggestions?start=${startDateTime}&end=${endDateTime}&day=${weekDayInt}`;

    if (time_period_id !== null) {
      searchUrl += `&time_period_id=${time_period_id}`;
    }

    fetch(searchUrl, {
      method: "GET",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
    })
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
        language: languageInput.value,
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
            extendedProps: data.extendedProps,
          },
          "shifts"
        );
        shiftModal.hide();
        calendar.unselect();
        refreshPendingShifts();
        if (modalDelete.classList.contains("d-block")) {
          removeEvent(document.getElementById("shift-id").value, true);
        }
        calendar.refetchEvents();
      }
    })
    .catch((error) => {
      console.log("An error occurred: " + error.message);
    });
  modalSave.disabled = false;
  modalSave.querySelector("span").classList.add("d-none");
};

const copyToNextWeek = () => {
  var isConfirmed = window.confirm(
    "Are you sure you want to copy this week's shifts to the next week's?"
  );

  if (isConfirmed) {
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
  }
};

const confirmCurrentWeekShifts = () => {
  var isConfirmed = window.confirm(
    "Are you sure you want to confirm this week's shifts?"
  );

  if (isConfirmed) {
    fetch("/admin/shifts/confirm_current_week_shifts", {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        end_of_week: calendar.currentData.dateProfile.currentRange.end,
      }),
    }).then((response) => {
      console.log("response", response);
      if (response.ok) {
        console.log("ok");
        calendar.refetchEvents();
        calendar.gotoDate(
          new Date(
            calendar.currentData.dateProfile.currentRange.start.getTime()
          )
        );
      }
    });
  }
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
    toggleShiftReason(reasonInput);
    shiftModal.show();
  });
};

document.addEventListener('DOMContentLoaded', function() {
  const selectAllCheckbox = document.getElementById('selectAllShifts');
  const shiftCheckboxes = document.querySelectorAll('input[type="checkbox"][id^="shift_"]');

  selectAllCheckbox.addEventListener('change', function() {
    shiftCheckboxes.forEach(checkbox => {
      checkbox.checked = this.checked;
    });
  });
});

function openPendingModal() {
  pendingShiftsModal.show();




}

document.addEventListener('DOMContentLoaded', function() {
  const confirmShiftsButton = document.getElementById('confirmShiftsButton');
  confirmShiftsButton.addEventListener('click', function() {
    openPendingModal();
  });
});

const modifyEvent = (arg) => {
  fetch("/admin/shifts/" + arg.event.id, {
    method: "PUT",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      start_datetime: arg.event.start.toISOString().slice(0, -5),
      end_datetime: arg.event.end.toISOString().slice(0, -5),
      ...(reasonInput.value === "Training" && {
        training_id: trainingIdInput.value,
        language: languageInput.value,
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
      startPicker.setDate(Date.parse(data.start_datetime.slice(0, -6)));
      endPicker.setDate(Date.parse(data.end_datetime.slice(0, -6)));
      reasonInput.value = data.reason;

      if (data.reason === "Training") {
        trainingIdInput.value = data.training_id;
        languageInput.value = data.language;
        courseInput.value = data.course;
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
      toggleShiftReason(reasonInput);
      shiftModal.show();
    });
};

const updateHours = () => {
  const startDate = calendar.view.activeStart;
  const endDate = calendar.view.activeEnd;

  fetch(
    `/admin/shifts/get_users_hours_between_dates?start_date=${startDate}&end_date=${endDate}`,
    {
      method: "GET",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
    }
  )
    .then((res) => res.json())
    .then((data) => {
      Object.keys(data).map((u) => {
        document.getElementById(
          `user-hour-counter-${u}`
        ).innerText = `${data[u]} hour(s)`;
      });
    })
    .catch((error) => {
      console.log("An error occurred: " + error.message);
    });
};

document.addEventListener('DOMContentLoaded', function() {
  const selectAllCheckbox = document.getElementById('selectAllShifts');
  const shiftCheckboxes = document.querySelectorAll('input[type="checkbox"][id^="shift_"]');

  selectAllCheckbox.addEventListener('change', function() {
    shiftCheckboxes.forEach(checkbox => {
      checkbox.checked = this.checked;
    });
  });

  document.getElementById('confirmSelectedShiftsButton').addEventListener('click', () => {
    const selectedShiftIds = Array.from(shiftCheckboxes)
                                  .filter(chk => chk.checked)
                                  .map(chk => chk.value);
   
  });
});


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
  toggleShiftReason(el.target);
});

function toggleShiftReason(el) {
  if (el.value === "Training") {
    trainingContainer.style.display = "block";
  } else {
    trainingContainer.style.display = "none";
  }
}

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

