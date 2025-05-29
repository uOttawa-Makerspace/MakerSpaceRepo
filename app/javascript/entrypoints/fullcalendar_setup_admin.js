import { Calendar } from "@fullcalendar/core";
import rrulePlugin from "@fullcalendar/rrule";
import timeGridPlugin from "@fullcalendar/timegrid";
import dayGridPlugin from "@fullcalendar/daygrid";
import interactionPlugin from "@fullcalendar/interaction";

import { rrulestr } from "rrule";

import { Tooltip } from "bootstrap";

import { isAllDay } from "./calendar_helper.js";
import { eventClick, eventCreate } from "./calendar.js";

document.addEventListener("turbo:load", async () => {
  const calendarEl = document.getElementById("calendar");

  const calendar = new Calendar(calendarEl, {
    plugins: [timeGridPlugin, dayGridPlugin, rrulePlugin, interactionPlugin],
    initialView: "timeGridWeek",
    headerToolbar: {
      left: "prev,next,today",
      center: "title",
      right: "timeGridWeek,dayGridMonth",
    },
    scrollTime: "08:00:00",
    selectable: true,
    selectMirror: true,
    selectMinDistance: "30",
    height: "75vh",
    eventDidMount: (info) => {
      new Tooltip(info.el, {
        title:
          info.event.title +
          (info.event.extendedProps.description
            ? `<br><i>${info.event.extendedProps.description}</i>`
            : ""),
        html: true,
      });
    },
    eventClick: (info) => eventClick(info.event),
    select: (info) => eventCreate(info),
  });

  // Init events
  const eventsRes = await fetch(
    "/admin/events/json/" + document.getElementById("space_id").value,
  ).catch((error) => console.log(error));
  const eventsData = await eventsRes.json();

  eventsData.forEach((eventSource) => {
    // If the rrule of any event source is present, remove \r
    eventSource.events.forEach((event) => {
      if (event.rrule) event.rrule = rrulestr(event.rrule).toString();
    });

    calendar.addEventSource(eventSource);
    appendCheckbox(
      eventSource,
      document.getElementById("events_checkbox_container"),
      "hidden_events",
    );
  });

  // Init staff unavailabilities
  const res = await fetch(
    "/admin/calendar/json/" + document.getElementById("space_id").value,
  ).catch((error) => console.log(error));
  const data = await res.json();

  const staffUnavailabilitiesEventSources = generateEventsFromStaffData(data);

  createAllStaffCheckbox();

  staffUnavailabilitiesEventSources.forEach((eventSource) => {
    calendar.addEventSource(eventSource);
    appendCheckbox(
      eventSource,
      document.getElementById("staff_checkbox_container"),
      "hidden_staff",
      document.querySelector(".all_checkbox"),
      "staff",
    );
  });

  // Init other calendars
  const myCalRes = await fetch(
    "/admin/calendar/ics_to_json?url=" +
      encodeURI(
        "https://outlook.office365.com/owa/calendar/0735be293f0049deb6033980c56fdfc1@uottawa.ca/9e0d5369bcea43c8b2179c4373edc2798901470964911707346/calendar.ics&background_color=SlateBlue&name=Max's+Calendar",
      ),
  ).catch((error) => console.log(error));
  const myCalEventSource = await myCalRes.json();

  const gCalRes = await fetch(
    "/admin/calendar/ics_to_json?url=" +
      encodeURI(
        "https://calendar.google.com/calendar/ical/c_g1bk6ctpenjeko2dourrr0h6pc%40group.calendar.google.com/public/basic.ics&background_color=pink&text_color=black&name=Makerspace",
      ),
  ).catch((error) => console.log(error));
  const gCalEventSource = await gCalRes.json();

  calendar.addEventSource(myCalEventSource);
  calendar.addEventSource(gCalEventSource);

  appendCheckbox(
    myCalEventSource,
    document.getElementById("calendars_checkbox_container"),
    "hidden_calendars",
  );
  appendCheckbox(
    gCalEventSource,
    document.getElementById("calendars_checkbox_container"),
    "hidden_calendars",
  );

  // Render and SHOW IT!!!
  document.getElementById("calendar_container").style.display = "block";
  document.getElementById("spinner_container").style.display = "none";

  calendar.render();
  document.querySelector(".fc-timegrid-slots tbody tr").style.height = "120px";

  /**
   * @param {Array} data - The array of staff members returned from the server. NOT AN EVENT LIST! Since we want the individual staff details (name, color, etc.) to be displayed in the checkboxes which will be used to filter the events.
   * @param {Array} hiddenStaff - The array of staff IDs that are hidden from query params. This is used to filter out events for those staff members.
   * @returns {Object} - FullCalendar event source object.
   * @description This function generates events from the staff data returned from the server.
   * THIS SHOULD PROBABLY BE DONE IN THE CONTROLLER
   */
  function generateEventsFromStaffData(data) {
    try {
      const allUnavails = [];
      data.map((staff) => {
        const unavails = staff.unavailabilities.map((unavailability) => {
          const event = {
            id: unavailability.id,
            groupId: staff.id,
            start: unavailability.start_date,
            end: unavailability.end_date,
            title: unavailability.title,
            allDay: isAllDay(
              unavailability.start_date,
              unavailability.end_date,
            ),
            extendedProps: {
              name: staff.name,
              description: unavailability.extendedProps.description,
            },
          };

          if (unavailability.recurrence_rule) {
            try {
              const rule = rrulestr(unavailability.recurrence_rule);
              event.rrule = rule.toString();
            } catch (e) {
              console.warn(
                "Invalid recurrence rule:",
                unavailability.recurrence_rule,
                e,
              );
            }
          }

          return event;
        });

        // If there are no unavailabilities for this staff member, we add a placeholder event
        if (unavails.length === 0)
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
                  name: staff.name + " (No unavailabilities yet)",
                },
              },
            ],
            id: staff.id.toString(),
            color: staff.color,
          });

        // Unshift to prepend to ensure any staff who haven't set their unavailability yet are at the bottom
        allUnavails.unshift({
          events: unavails,
          id: staff.id.toString(),
          color: staff.color,
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
  function createAllStaffCheckbox() {
    const allCheckboxDiv = document.createElement("div");
    allCheckboxDiv.className = "form-check m-2 d-flex align-items-center gap-2";

    const { checkbox: allCheckbox, label: allLabel } = createCheckboxElement(
      "all",
      "All Staff",
      "#919191",
      " all_checkbox",
    );
    const container = document.getElementById("staff_checkbox_container");
    const urlParams = new URLSearchParams(window.location.search);
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
          (source) => source.id === checkbox.value,
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

    const urlParams = new URLSearchParams(window.location.search);
    const hiddenCalendars = urlParams.get(urlParam) || "";
    const hiddenCalendarsArray = hiddenCalendars
      .split(",")
      .filter((id) => id !== "");

    const isHidden = hiddenCalendarsArray.includes(eventSource.id.toString());

    const checkboxDiv = document.createElement("div");
    checkboxDiv.className = "form-check m-2 d-flex align-items-center gap-2";

    const { checkbox, label } = createCheckboxElement(
      eventSource.id,
      eventSource.events[0].extendedProps.name,
      eventSource.color,
      classes,
    );
    checkbox.style.accentColor = eventSource.events[0].textColor;
    checkbox.checked = !isHidden;

    checkbox.addEventListener("change", (e) => {
      updateHiddenParam(checkbox.value, urlParam, !e.target.checked);
      calendar.getEventSourceById(eventSource.id);

      if (e.target.checked) {
        calendar.addEventSource(eventSource);
      }
      if (!e.target.checked) {
        if (groupCheckboxElem) {
          groupCheckboxElem.checked = false;
        }
        calendar.getEventSourceById(eventSource.id).remove();
      }
    });

    checkboxDiv.appendChild(checkbox);
    checkboxDiv.appendChild(label);
    container.appendChild(checkboxDiv);

    // Also remove the event source if it is hidden
    if (isHidden) {
      calendar.getEventSourceById(eventSource.id).remove();
    }
  }

  /**
   * @param {String} id - The ID of the checkbox (and, as a result, the staff/event id).
   * @param {String} name - The name of the checkbox (displayed next to the checkbox).
   * @param {String} color - The color of the checkbox (used for styling).
   * @param {String} classes - Additional classes to add to the checkbox.
   * @returns {Object} - An object containing the checkbox and label elements.
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

    calendar.refetchEvents();
  }
});
