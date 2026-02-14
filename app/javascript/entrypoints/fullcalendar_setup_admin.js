import { Calendar } from "@fullcalendar/core";
import rrulePlugin from "@fullcalendar/rrule";
import timeGridPlugin from "@fullcalendar/timegrid";
import dayGridPlugin from "@fullcalendar/daygrid";
import interactionPlugin from "@fullcalendar/interaction";

import { rrulestr } from "rrule";

import { Tooltip } from "bootstrap";

import { eventClick, eventCreate } from "./calendar_helper.js";

document.addEventListener("turbo:load", async () => {
  const calendarEl = document.getElementById("calendar");
  if (!calendarEl) return;

  let hiddenUserIds = new Set();

  const calendar = new Calendar(calendarEl, {
    plugins: [timeGridPlugin, dayGridPlugin, rrulePlugin, interactionPlugin],
    timeZone: "America/Toronto",
    initialView: "timeGridWeek",
    headerToolbar: {
      left: "prev,next,today toggleEventOverlap",
      center: "title",
      right: "toggleWeekends timeGridWeek,dayGridMonth",
    },
    slotMinTime: "07:00:00",
    slotMaxTime: "22:00:00",
    scrollTime: "07:00:00",
    nowIndicator: true,
    slotEventOverlap: localStorage.fullCalendarEventOverlap === "true",
    selectable: true,
    selectMirror: true,
    selectMinDistance: "15",
    height: "80vh",
    customButtons: {
      toggleWeekends: {
        text: "",
        click: () => {
          calendar.setOption("weekends", !calendar.getOption("weekends"));

          document.querySelector(".fc-toggleWeekends-button").innerHTML =
            calendar.getOption("weekends") ? "Hide Weekends" : "Show Weekends";
        },
      },
      toggleEventOverlap: {
        text: "",
        click: () => {
          localStorage.fullCalendarEventOverlap =
            !calendar.getOption("slotEventOverlap");

          calendar.setOption(
            "slotEventOverlap",
            !calendar.getOption("slotEventOverlap"),
          );

          document.querySelector(".fc-toggleEventOverlap-button").innerHTML =
            calendar.getOption("slotEventOverlap")
              ? "Disable Event Overlap"
              : "Enable Event Overlap";
        },
      },
    },
    eventDidMount: (info) => {
      // fade in event
      requestAnimationFrame(() => {
        info.el.classList.add("fade-in");
      });

      // create event tooltip
      new Tooltip(info.el, {
        title:
          info.event.title +
          (info.event.extendedProps.description
            ? `<br><i>${info.event.extendedProps.description}</i>`
            : ""),
        html: true,
      });

      // add user color bg gradient
      if (info.event.extendedProps.background) {
        info.el.setAttribute(
          "style",
          `background: ${info.event.extendedProps.background}`,
        );
      }

      // Add visual indicator for admin-created unavailabilities
      if (info.event.extendedProps.isAdminCreated) {
        info.el.classList.add("admin-created-unavailability");
      }
    },
    eventClick: (info) => eventClick(info.event),
    select: (info) => eventCreate(info),
    initialDate: localStorage.fullCalendarDefaultDateAdmin,
    datesSet: (info) => {
      // recall dates on refresh
      const date = new Date(info.view.currentStart);
      localStorage.fullCalendarDefaultDateAdmin = date.toISOString();

      document
        .querySelectorAll(".view_start_date")
        .forEach((elem) => (elem.value = info.startStr));
      document
        .querySelectorAll(".view_end_date")
        .forEach((elem) => (elem.value = info.endStr));

      // update publish/delete button names
      const pubDraftButt = document.getElementById("publish_drafts_button");
      const delDraftButt = document.getElementById("delete_drafts_button");
      if (pubDraftButt && delDraftButt) {
        if (info.view.type === "timeGridWeek") {
          pubDraftButt.innerText = "Publish This Week's Drafts";
          delDraftButt.innerText = "Delete This Week's Drafts";
        } else {
          pubDraftButt.innerText = "Publish This Month's Drafts";
          delDraftButt.innerText = "Delete This Month's Drafts";
        }
      }

      updateUserHourBadges();
    },
  });

  // Init events
  const spaceIdElem = document.getElementById("space_id");
  if (!spaceIdElem) {
    console.error("space_id element not found");
    return;
  }

  const eventsRes = await fetch(
    "/admin/events/json/" + spaceIdElem.value,
  ).catch((error) => console.log(error));
  const eventsData = await eventsRes.json();

  eventsData.forEach((eventSource) => {
    eventSource.events.forEach((event) => {
      if (event.rrule) {
        try {
          event.rrule = rrulestr(event.rrule).toString();
        } catch (e) {
          console.error("Error parsing rrule:", e, event.rrule);
        }
      }
    });

    const checkboxContainer = document.getElementById(
      "events_checkbox_container",
    );
    if (checkboxContainer) {
      appendCheckbox(eventSource, checkboxContainer, "hidden_events");
    }
  });

  calendar.addEventSource({
    id: "staffEvents",
    events: (info, successCallback) => {
      const filtered = [];
      for (const src of eventsData) {
        for (const ev of src.events) {
          const assigned = (ev.extendedProps.assignedUsers || []).map((u) =>
            u.id.toString(),
          );
          const visible = !assigned.every((id) => hiddenUserIds.has(id));
          if (visible) filtered.push(ev);
        }
      }
      successCallback(filtered);
    },
  });

  // Init staff unavailabilities
  const res = await fetch(
    "/admin/calendar/unavailabilities_json/" + spaceIdElem.value,
  ).catch((error) => console.log(error));
  const data = await res.json();

  const staffUnavailabilitiesEventSources = generateEventsFromStaffData(data);

  createAllStaffCheckboxes();

  staffUnavailabilitiesEventSources.forEach((eventSource) => {
    calendar.addEventSource(eventSource);
    const staffCheckboxContainer = document.getElementById(
      "staff_checkbox_container",
    );
    if (staffCheckboxContainer) {
      appendCheckbox(
        eventSource,
        staffCheckboxContainer,
        "hidden_staff",
        document.querySelector(".all_checkbox"),
        "staff",
      );
    }
  });

  // Render and SHOW IT!!!
  const calendarContainer = document.getElementById("calendar_container");
  const spinnerContainer = document.getElementById("spinner_container");
  if (calendarContainer) calendarContainer.style.display = "block";
  if (spinnerContainer) spinnerContainer.style.display = "none";
  calendar.render();

  // scroll to fullcalendar by default
  window.scrollTo(0, document.getElementById("calendar").offsetTop - 180);

  // Set custom button text
  const toggleWeekendsBtn = document.querySelector(".fc-toggleWeekends-button");
  if (toggleWeekendsBtn) {
    toggleWeekendsBtn.innerHTML = calendar.getOption("weekends")
      ? "Hide Weekends"
      : "Show Weekends";
  }

  const toggleOverlapBtn = document.querySelector(
    ".fc-toggleEventOverlap-button",
  );
  if (toggleOverlapBtn) {
    toggleOverlapBtn.innerHTML = calendar.getOption("slotEventOverlap")
      ? "Disable Event Overlap"
      : "Enable Event Overlap";
  }

  // Init imported calendars
  const importedCalendarsRes = await fetch(
    "/admin/calendar/imported_calendars_json/" + spaceIdElem.value,
  ).catch((error) => console.log(error));
  const importedCalendars = await importedCalendarsRes.json();

  importedCalendars.forEach((eventSource) => {
    calendar.addEventSource(eventSource);

    const calendarsCheckboxContainer = document.getElementById(
      "calendars_checkbox_container",
    );
    if (calendarsCheckboxContainer) {
      appendCheckbox(
        eventSource,
        calendarsCheckboxContainer,
        "hidden_calendars",
      );
    }
  });

  const importedCalStatusSpan = document.getElementById(
    "imported_calendars_status",
  );
  if (importedCalStatusSpan) {
    if (importedCalendars.length) {
      importedCalStatusSpan.style.display = "none";
    } else {
      importedCalStatusSpan.innerText = "No calendars found";
    }
  }

  /**
   * @param {Array} data - The array of staff members returned from the server.
   * @returns {Object} - FullCalendar event source object.
   */
  function generateEventsFromStaffData(data) {
    try {
      const allUnavails = [];
      data.map((staff) => {
        // If there are no unavailabilities for this staff member, we add a placeholder event
        if (staff.unavailabilities.length === 0)
          return allUnavails.push({
            events: [
              {
                id: "no-unavailabilties",
                groupId: staff.id,
                start: new Date("2000-01-01T00:00:00"),
                end: new Date("2000-01-01T00:00:00"),
                title: "No Unavailabilities for this user",
                allDay: true,
                extendedProps: {
                  name: staff.name + " (0 unavailabilities)",
                },
              },
            ],
            id: staff.id,
            color: staff.color,
          });

        // Process events with rrule parsing
        const processedEvents = staff.unavailabilities.map((u) => {
          // Parse rrule if present
          if (u.rrule) {
            try {
              u.rrule = rrulestr(u.rrule).toString();
            } catch (e) {
              console.error("Error parsing unavailability rrule:", e, u.rrule);
            }
          }

          return {
            ...u,
            extendedProps: {
              ...u.extendedProps,
              eventType: "unavailability",
              userId: staff.id,
              isAdminCreated: u.title?.includes("(Admin)"),
            },
          };
        });

        // Unshift to prepend to ensure any staff who haven't set their unavailability yet are at the bottom
        allUnavails.unshift({
          id: staff.id,
          color: staff.color,
          events: processedEvents,
        });
      });

      return allUnavails;
    } catch (error) {
      console.error("Error fetching unavailability data:", error);
      return [];
    }
  }

  /**
   * Creates a checkbox for all staff members to toggle visibility
   */
  function createAllStaffCheckboxes() {
    const allCheckboxDiv = document.createElement("div");
    allCheckboxDiv.className = "m-2 d-flex align-items-center gap-1";

    const { checkbox: allEventsCheckbox, label: allEventsLabel } =
      createCheckboxElement("all", " / ", "#919191", "all_events_checkbox");
    const { checkbox: allCheckbox, label: allLabel } = createCheckboxElement(
      "all",
      "All Staff",
      "#919191",
      "all_checkbox",
    );

    const container = document.getElementById("staff_checkbox_container");
    if (!container) return;

    const urlParams = new URLSearchParams(window.location.search);

    // For staff events
    const hiddenStaffEvents = urlParams.get("hidden_staff_events") || "";
    const hiddenStaffEventsArray = hiddenStaffEvents
      .split(",")
      .filter((id) => id !== "");
    hiddenUserIds = new Set(hiddenStaffEventsArray);
    allEventsCheckbox.checked = hiddenStaffEventsArray.length === 0;
    allEventsCheckbox.addEventListener("change", (e) => {
      toggleAllStaffEventsCheckboxes();
    });
    const toggleAllStaffEventsCheckboxes = () => {
      const checkboxes = container.querySelectorAll(
        "input[type='checkbox'].staff_events",
      );
      checkboxes.forEach((checkbox) => {
        checkbox.checked = allEventsCheckbox.checked;
        const event = new Event("change");
        checkbox.dispatchEvent(event);
      });
    };

    // For staff unavails
    const hiddenStaff = urlParams.get("hidden_staff") || "";
    const hiddenStaffArray = hiddenStaff.split(",").filter((id) => id !== "");
    allCheckbox.checked = hiddenStaffArray.length === 0;
    allCheckbox.addEventListener("change", (e) => {
      toggleAllStaffCheckboxes();
    });
    const toggleAllStaffCheckboxes = () => {
      const checkboxes = container.querySelectorAll(
        "input[type='checkbox'].staff",
      );
      checkboxes.forEach((checkbox) => {
        checkbox.checked = allCheckbox.checked;
        updateHiddenParam(checkbox.value, "hidden_staff", !allCheckbox.checked);

        const eventSource = staffUnavailabilitiesEventSources.find(
          (source) => source.id.toString() === checkbox.value,
        );
        const eventSourceFromCalendar = calendar.getEventSourceById(
          checkbox.value,
        );

        if (allCheckbox.checked && !eventSourceFromCalendar) {
          calendar.addEventSource(eventSource);
        } else if (!allCheckbox.checked && eventSourceFromCalendar) {
          calendar.getEventSourceById(checkbox.value).remove();
        }
      });
    };

    allCheckboxDiv.appendChild(allEventsCheckbox);
    allCheckboxDiv.appendChild(allEventsLabel);
    allCheckboxDiv.appendChild(allCheckbox);
    allCheckboxDiv.appendChild(allLabel);
    container.appendChild(allCheckboxDiv);
  }

  /**
   * Appends a checkbox for an event source
   */
  function appendCheckbox(
    eventSource,
    containerElem,
    urlParam,
    groupCheckboxElem = null,
    classes = "",
  ) {
    const container = containerElem;
    if (container.previousElementSibling) {
      container.previousElementSibling.style.display = "block";
    }

    const urlParams = new URLSearchParams(window.location.search);
    const hiddenCalendars = urlParams.get(urlParam) || "";
    const hiddenCalendarsArray = hiddenCalendars
      .split(",")
      .filter((id) => id !== "");

    const isHidden = hiddenCalendarsArray.includes(eventSource.id.toString());

    const checkboxDiv = document.createElement("div");
    checkboxDiv.className = "m-2 d-flex align-items-center gap-1";

    const { checkbox, label } = createCheckboxElement(
      eventSource.id,
      eventSource.events?.[0]?.extendedProps?.name || "Unnamed Calendar",
      eventSource.color,
      classes,
    );
    checkbox.style.accentColor = eventSource.events?.[0]?.textColor;
    checkbox.checked = !isHidden;

    checkbox.addEventListener("change", (e) => {
      updateHiddenParam(checkbox.value, urlParam, !e.target.checked);
      if (e.target.checked) {
        calendar.addEventSource(eventSource);
      } else {
        if (groupCheckboxElem) groupCheckboxElem.checked = false;
        calendar.getEventSourceById(eventSource.id)?.remove();
      }
    });

    checkboxDiv.appendChild(checkbox);
    checkboxDiv.appendChild(label);
    container.appendChild(checkboxDiv);

    if (classes.includes("staff")) {
      const { checkbox: eventsCheckbox, label: eventsLabel } =
        createCheckboxElement(
          `events-${eventSource.id}`,
          " / ",
          eventSource.color,
          "staff_events",
        );

      const isStaffEventsHidden = hiddenUserIds.has(eventSource.id.toString());
      eventsCheckbox.checked = !isStaffEventsHidden;

      eventsCheckbox.addEventListener("change", (e) => {
        const userId = eventSource.id.toString();
        if (e.target.checked) {
          hiddenUserIds.delete(userId);
        } else {
          hiddenUserIds.add(userId);
          const allEventsCheckboxElem = document.querySelector(
            ".all_events_checkbox",
          );
          if (allEventsCheckboxElem) allEventsCheckboxElem.checked = false;
        }
        updateHiddenParam(userId, "hidden_staff_events", !e.target.checked);
        calendar.refetchEvents();
      });

      checkboxDiv.insertBefore(eventsLabel, checkboxDiv.firstChild);
      checkboxDiv.insertBefore(eventsCheckbox, checkboxDiv.firstChild);
    }

    if (isHidden) {
      calendar.getEventSourceById(eventSource.id)?.remove();
    }
  }

  /**
   * Creates a checkbox element.
   */
  function createCheckboxElement(id, name, color, classes = "") {
    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.className = "form-check-input " + classes;
    checkbox.style.backgroundColor = color;
    checkbox.style.borderColor = color;
    checkbox.style.width = "20px";
    checkbox.style.height = "20px";
    checkbox.id = `checkbox-${id}`;
    checkbox.value = id;

    const label = document.createElement("label");
    label.className = "form-check-label";
    label.htmlFor = `checkbox-${id}`;
    label.textContent = name;

    return { checkbox, label };
  }

  /**
   * Updates the URL parameter.
   */
  function updateHiddenParam(id, param, shouldHide) {
    const url = new URL(window.location.href);
    const params = new URLSearchParams(url.search);
    let hiddenParam = params.get(param) || "";
    let hiddenParamArray = hiddenParam
      .split(",")
      .filter((newId) => newId !== "");

    if (shouldHide) {
      if (!hiddenParamArray.includes(id.toString())) {
        hiddenParamArray.push(id.toString());
      }
    } else {
      hiddenParamArray = hiddenParamArray.filter(
        (paramId) => paramId !== id.toString(),
      );
    }

    if (hiddenParamArray.length > 0) {
      params.set(param, hiddenParamArray.join(","));
    } else {
      params.delete(param);
    }

    url.search = params.toString();
    window.history.pushState({}, "", url.toString());

    return hiddenParamArray;
  }

  // Handle staff hours worked badges
  function updateUserHourBadges() {
    const eventsInView = calendar
      ?.getEvents()
      .filter(
        (eventImpl) =>
          eventImpl.start >= calendar.view.activeStart &&
          eventImpl.end <= calendar.view.activeEnd &&
          eventImpl._def.extendedProps?.assignedUsers?.length >= 1,
      );

    document.querySelectorAll(".staff[id^='checkbox-']").forEach((checkbox) => {
      const userId = checkbox.id.replace("checkbox-", "");
      const parent = checkbox.parentNode;
      let span = parent.querySelector(".user-hours");

      let userHours = 0;
      eventsInView.forEach((eventImpl) => {
        if (
          !eventImpl._def.extendedProps.assignedUsers.some(
            (user) => user.id == userId,
          )
        )
          return;

        userHours +=
          (eventImpl.end.getTime() - eventImpl.start.getTime()) /
          1000 /
          60 /
          60;
      });

      if (!span) {
        span = document.createElement("span");
        span.className = "user-hours px-2 py-1 bg-secondary-subtle rounded";
        span.style.minWidth = "max-content";
        parent.lastElementChild.style.flex = 1;
        parent.appendChild(span);
      }

      span.textContent = `${userHours} hrs`;
    });
  }
});
