import { Controller } from "@hotwired/stimulus";
import { Calendar } from "@fullcalendar/core";
import rrulePlugin from "@fullcalendar/rrule";
import timeGridPlugin from "@fullcalendar/timegrid";
import dayGridPlugin from "@fullcalendar/daygrid";
import interactionPlugin from "@fullcalendar/interaction";
import { rrulestr } from "rrule";
import { Tooltip } from "bootstrap";

import { eventClick, eventCreate } from "../src/calendar_helper.js";
import { applyEventBackground } from "../src/calendar_background.js";

// Titles and descriptions come from imported calendars, so they are text, never markup.
const escapeHtml = (text) =>
  String(text).replace(
    /[&<>"']/g,
    (char) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        char
      ],
  );

// A repeating row's rule as rrule.js writes it back, which is how the page has
// always handed it to the calendar; a rule it cannot read is drawn as sent.
function readRule(row) {
  if (!row.rrule) return row;
  try {
    return { ...row, rrule: rrulestr(row.rrule).toString() };
  } catch (error) {
    console.error("Error parsing rrule:", error, row.rrule);
    return row;
  }
}

// The rows of a feed for the calendar's range (?start&end).
async function fetchRange(url, info) {
  const range = new URLSearchParams({ start: info.startStr, end: info.endStr });
  const response = await fetch(`${url}?${range}`, {
    headers: { Accept: "application/json" },
  });
  if (!response.ok) throw new Error(`${url} answered ${response.status}`);
  return response.json();
}

// A calendar source that asks the feed once per range and draws the rows
// `visible` keeps, so a filter checkbox redraws without asking again. A failed
// request is forgotten, so the next redraw asks again.
function rangeSource(id, url, rowsOf, visible) {
  let fetched = { range: null, rows: Promise.resolve([]) };
  return {
    id,
    events: (info, success, failure) => {
      const range = `${info.startStr}/${info.endStr}`;
      if (fetched.range !== range) {
        const asked = { range, rows: fetchRange(url, info).then(rowsOf) };
        asked.rows.catch(() => (asked.range = null));
        fetched = asked;
      }
      fetched.rows.then((rows) => success(visible(rows)), failure);
    },
  };
}

// The values of the unticked boxes.
const unticked = (boxes) =>
  new Set(boxes.filter((box) => !box.checked).map((box) => box.value));

// Stimulus defines the target and value accessors at runtime; this tells the
// type checker.
const TypedController = /** @type {new () => Controller<HTMLElement> & {
  calendarTarget: HTMLElement,
  containerTarget: HTMLElement,
  spinnerTarget: HTMLElement,
  publishDraftsTarget: HTMLElement,
  deleteDraftsTarget: HTMLElement,
  allStaffTarget: HTMLInputElement,
  allStaffEventsTarget: HTMLInputElement,
  staffTargets: HTMLInputElement[],
  staffEventsTargets: HTMLInputElement[],
  eventTypeTargets: HTMLInputElement[],
  importedCalendarTargets: HTMLInputElement[],
  viewStartTargets: HTMLInputElement[],
  viewEndTargets: HTMLInputElement[],
  hoursTargets: HTMLElement[],
  eventsUrlValue: string,
  unavailabilitiesUrlValue: string,
  importedUrlValue: string,
}} */ (/** @type {unknown} */ (Controller));

// The admin calendar of a space: events, staff unavailabilities and imported
// calendars, each fetched for the range shown, filtered by the sidebar
// checkboxes (which the address keeps), with each staff member's hours.
export default class extends TypedController {
  static targets = [
    "calendar",
    "container",
    "spinner",
    "publishDrafts",
    "deleteDrafts",
    "allStaff",
    "allStaffEvents",
    "staff",
    "staffEvents",
    "eventType",
    "importedCalendar",
    "viewStart",
    "viewEnd",
    "hours",
  ];
  static values = {
    eventsUrl: String,
    unavailabilitiesUrl: String,
    importedUrl: String,
  };

  connect() {
    this.paintFilters();
    // A page restored from Turbo's cache still holds the calendar drawn before.
    this.calendarTarget.replaceChildren();
    this.calendar = new Calendar(this.calendarTarget, this.calendarOptions());

    this.containerTarget.style.display = "block";
    this.spinnerTarget.style.display = "none";
    this.calendar.render();
    this.labelToolbar();
    window.scrollTo(0, this.calendarTarget.offsetTop - 180);
  }

  disconnect() {
    this.calendar?.destroy();
    this.calendar = null;
  }

  // The colours come from settings, so the browser's own style parser decides
  // whether one is used.
  paintFilters() {
    this.element.querySelectorAll("input[data-color]").forEach((box) => {
      const input = /** @type {HTMLInputElement} */ (box);
      input.style.backgroundColor = input.dataset.color;
      input.style.borderColor = input.dataset.color;
    });
  }

  eventsSource() {
    return rangeSource(
      "events",
      this.eventsUrlValue,
      (groups) => groups.flatMap((group) => group.events).map(readRule),
      (rows) => this.visibleEvents(rows),
    );
  }

  unavailabilitySource() {
    return rangeSource(
      "unavailabilities",
      this.unavailabilitiesUrlValue,
      (staff) =>
        staff.flatMap((member) =>
          member.unavailabilities.map((row) => unavailabilityRow(member, row)),
        ),
      (rows) => {
        const hidden = unticked(this.staffTargets);
        return rows.filter(
          (row) => !hidden.has(String(row.extendedProps.userId)),
        );
      },
    );
  }

  importedSource() {
    return rangeSource(
      "imported",
      this.importedUrlValue,
      (calendars) =>
        calendars.flatMap((calendar) =>
          calendar.events.map((row) => ({ ...row, color: calendar.color })),
        ),
      (rows) => {
        const hidden = unticked(this.importedCalendarTargets);
        return rows.filter((row) => !hidden.has(row.groupId));
      },
    );
  }

  // An event is shown when its type is ticked and at least one of the staff
  // assigned to it (or "Unassigned") has their events ticked.
  visibleEvents(rows) {
    const types = unticked(this.eventTypeTargets);
    const staff = unticked(this.staffEventsTargets);
    return rows.filter(
      (row) =>
        !types.has(row.extendedProps.eventType) &&
        !row.extendedProps.assignedUsers.every((user) =>
          staff.has(String(user.id)),
        ),
    );
  }

  toggleStaff({ target }) {
    if (!target.checked) this.allStaffTarget.checked = false;
    this.redraw("unavailabilities");
  }

  toggleAllStaff({ target }) {
    this.staffTargets.forEach((box) => (box.checked = target.checked));
    this.redraw("unavailabilities");
  }

  toggleStaffEvents({ target }) {
    if (!target.checked) this.allStaffEventsTarget.checked = false;
    this.redraw("events");
  }

  toggleAllStaffEvents({ target }) {
    this.staffEventsTargets.forEach((box) => (box.checked = target.checked));
    this.redraw("events");
  }

  toggleEventType() {
    this.redraw("events");
  }

  toggleImportedCalendar() {
    this.redraw("imported");
  }

  redraw(sourceId) {
    this.rememberHidden();
    this.calendar.getEventSourceById(sourceId).refetch();
  }

  // The address lists the unticked boxes of each kind, so a reload or a
  // shared link shows the same calendar.
  rememberHidden() {
    const url = new URL(window.location.href);
    Object.entries({
      hidden_staff: this.staffTargets,
      hidden_staff_events: this.staffEventsTargets,
      hidden_events: this.eventTypeTargets,
      hidden_calendars: this.importedCalendarTargets,
    }).forEach(([param, boxes]) => {
      const hidden = [...unticked(boxes)];
      if (hidden.length) url.searchParams.set(param, hidden.join(","));
      else url.searchParams.delete(param);
    });
    window.history.pushState({}, "", url.toString());
  }

  calendarOptions() {
    return {
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
      selectMinDistance: 15,
      height: "80vh",
      customButtons: {
        toggleWeekends: { text: "", click: () => this.toggleWeekends() },
        toggleEventOverlap: { text: "", click: () => this.toggleOverlap() },
      },
      eventDidMount: (info) => this.decorate(info),
      eventClick: (info) => eventClick(info.event),
      select: (info) => eventCreate(info),
      initialDate: localStorage.fullCalendarDefaultDateAdmin,
      datesSet: (info) => this.showRange(info),
      eventsSet: (events) => this.showHours(events),
      eventSources: [
        this.eventsSource(),
        this.unavailabilitySource(),
        this.importedSource(),
      ],
    };
  }

  toggleWeekends() {
    this.calendar.setOption("weekends", !this.calendar.getOption("weekends"));
    this.labelToolbar();
  }

  toggleOverlap() {
    const overlap = !this.calendar.getOption("slotEventOverlap");
    localStorage.fullCalendarEventOverlap = overlap;
    this.calendar.setOption("slotEventOverlap", overlap);
    this.labelToolbar();
  }

  labelToolbar() {
    const label = (name, text) => {
      const button = this.calendarTarget.querySelector(`.fc-${name}-button`);
      if (button) button.textContent = text;
    };
    label(
      "toggleWeekends",
      this.calendar.getOption("weekends") ? "Hide Weekends" : "Show Weekends",
    );
    label(
      "toggleEventOverlap",
      this.calendar.getOption("slotEventOverlap")
        ? "Disable Event Overlap"
        : "Enable Event Overlap",
    );
  }

  // Fades the event in, gives it a tooltip and the staff colours.
  decorate(info) {
    requestAnimationFrame(() => info.el.classList.add("fade-in"));
    const { description } = info.event.extendedProps;
    new Tooltip(info.el, {
      title:
        escapeHtml(info.event.title) +
        (description ? `<br><i>${escapeHtml(description)}</i>` : ""),
      html: true,
    });
    applyEventBackground(info.el, info.event.extendedProps.background);
    if (info.event.extendedProps.isAdminCreated) {
      info.el.classList.add("admin-created-unavailability");
    }
  }

  // Remembers the date shown, and gives the draft buttons the range shown.
  showRange(info) {
    localStorage.fullCalendarDefaultDateAdmin = new Date(
      info.view.currentStart,
    ).toISOString();
    this.viewStartTargets.forEach((field) => (field.value = info.startStr));
    this.viewEndTargets.forEach((field) => (field.value = info.endStr));
    const span = info.view.type === "timeGridWeek" ? "Week" : "Month";
    this.publishDraftsTarget.innerText = `Publish This ${span}'s Drafts`;
    this.deleteDraftsTarget.innerText = `Delete This ${span}'s Drafts`;
  }

  // Each staff member's hours in the events shown that lie within the view.
  showHours(events) {
    const { activeStart, activeEnd } = this.calendar.view;
    const shifts = events.filter(
      (event) =>
        event.start >= activeStart &&
        event.end <= activeEnd &&
        event.extendedProps.assignedUsers?.length >= 1,
    );
    this.hoursTargets.forEach((badge) => {
      const hours = shifts
        .filter((event) =>
          event.extendedProps.assignedUsers.some(
            (user) => String(user.id) === badge.dataset.userId,
          ),
        )
        .reduce(
          (sum, event) =>
            sum +
            (event.end.getTime() - event.start.getTime()) / 1000 / 60 / 60,
          0,
        );
      badge.textContent = `${hours} hrs`;
    });
  }
}

// An unavailability row as the calendar and the event dialog read it.
function unavailabilityRow(member, row) {
  return {
    ...readRule(row),
    color: member.color,
    extendedProps: {
      ...row.extendedProps,
      eventType: "unavailability",
      userId: member.id,
      isAdminCreated: row.title?.includes("(Admin)"),
    },
  };
}
