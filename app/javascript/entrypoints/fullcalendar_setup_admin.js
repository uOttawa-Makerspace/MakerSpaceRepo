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
      if (info.view.type === "timeGridWeek") {
        pubDraftButt.innerText = "Publish This Week's Drafts";
        delDraftButt.innerText = "Delete This Week's Drafts";
      } else {
        pubDraftButt.innerText = "Publish This Month's Drafts";
        delDraftButt.innerText = "Delete This Month's Drafts";
      }

      updateUserHourBadges();
    },
  });

  // Init events
  const eventsRes = await fetch(
    "/admin/events/json/" + document.getElementById("space_id").value,
  ).catch((error) => console.log(error));
  const eventsData = await eventsRes.json();

  eventsData.forEach((eventSource) => {
    eventSource.events.forEach((event) => {
      if (event.rrule) event.rrule = rrulestr(event.rrule).toString();
    });

    appendCheckbox(
      eventSource,
      document.getElementById("events_checkbox_container"),
      "hidden_events",
    );
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
    "/admin/calendar/unavailabilities_json/" +
      document.getElementById("space_id").value,
  ).catch((error) => console.log(error));
  const data = await res.json();

  const staffUnavailabilitiesEventSources = generateEventsFromStaffData(data);

  createAllStaffCheckboxes();

  staffUnavailabilitiesEventSources.forEach((eventSource) => {
    calendar.addEventSource(eventSource);
    // Unavails cb
    appendCheckbox(
      eventSource,
      document.getElementById("staff_checkbox_container"),
      "hidden_staff",
      document.querySelector(".all_checkbox"),
      "staff",
    );
  });

  // Render and SHOW IT!!!
  document.getElementById("calendar_container").style.display = "block";
  document.getElementById("spinner_container").style.display = "none";
  calendar.render();

  // Set custom button text
  document.querySelector(".fc-toggleWeekends-button").innerHTML =
    calendar.getOption("weekends") ? "Hide Weekends" : "Show Weekends";

  document.querySelector(".fc-toggleEventOverlap-button").innerHTML =
    calendar.getOption("slotEventOverlap")
      ? "Disable Event Overlap"
      : "Enable Event Overlap";

  // Init imported calendars
  const importedCalendarsRes = await fetch(
    "/admin/calendar/imported_calendars_json/" +
      document.getElementById("space_id").value,
  ).catch((error) => console.log(error));
  const importedCalendars = await importedCalendarsRes.json();

  importedCalendars.forEach((eventSource) => {
    calendar.addEventSource(eventSource);

    appendCheckbox(
      eventSource,
      document.getElementById("calendars_checkbox_container"),
      "hidden_calendars",
    );
  });
  const importedCalStatusSpan = document.getElementById(
    "imported_calendars_status",
  );
  if (importedCalendars.length) {
    importedCalStatusSpan.style.display = "none";
  } else {
    importedCalStatusSpan.innerText = "No calendars found";
  }

  /**
   * @param {Array} data - The array of staff members returned from the server. NOT AN EVENT LIST! Since we want the individual staff details (name, color, etc.) to be displayed in the checkboxes which will be used to filter the events.
   * @param {Array} hiddenStaff - The array of staff IDs that are hidden from query params. This is used to filter out events for those staff members.
   * @returns {Object} - FullCalendar event source object.
   * @description This function generates events from the staff data returned from the server.
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

        // Unshift to prepend to ensure any staff who haven't set their unavailability yet are at the bottom
        allUnavails.unshift({
          id: staff.id,
          color: staff.color,
          events: staff.unavailabilities,
        });
      });

      return allUnavails;
    } catch (error) {
      console.error("Error fetching unavailability data:", error);
    }
  }

  /**
   * @description Creates a checkbox for all staff members to toggle visibility of all staff checkboxes and their events.
   * @returns {void}
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
        // Unforch we can't just dispatch the change event here since we aren't toggling the display property, we're adding and remove event sources... so we just need to check if the event source is already shown or hidden and go from there
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
   * @param {Array} eventSource - EventSourceObject -> https://fullcalendar.io/docs/event-source-object. Must contain an `id` and `events` property. `events` should have `color` and `extendedProps.name` properties.
   * @param {HTMLElement} containerElem - The container element to append the checkbox to.
   * @param {String} urlParam - The URL parameter to update when the checkbox is checked/unchecked.
   * @param {HTMLElement=null} groupCheckboxElem - The group checkbox element to toggle visibility of the calendar.
   * @param {String=""} classes - Additional classes to add to the checkbox.
   * @returns {void}
   * @description Creates a checkbox for a given event source and adds it to the DOM. Hides the calendar if the checkbox is unchecked on page load and responds to checkbox state changes.
   */
  function appendCheckbox(
    eventSource,
    containerElem,
    urlParam,
    groupCheckboxElem = null,
    classes = "",
  ) {
    const container = containerElem;
    container.previousElementSibling.style.display = "block";

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
          document.querySelector(".all_events_checkbox").checked = false;
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
   * @param {String} id - The ID of the checkbox (and, as a result, the staff/event id).
   * @param {String} name - The name of the checkbox (displayed next to the checkbox).
   * @param {String} color - The color of the checkbox (used for styling).
   * @param {String} classes - Additional classes to add to the checkbox.
   * @returns {Object} An object containing the checkbox and label elements.
   * @description Creates a checkbox element with the given parameters.
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
   * @param {string} id - The ID of the checkbox (and, as a result, the staff/event id).
   * @param {string} param - The URL parameter to update.
   * @param {boolean} shouldHide - Whether to hide or show the event.
   * @returns {Array} - An array of the hidden params
   * @description Updates the URL parameter and refreshes the calendar events.
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
