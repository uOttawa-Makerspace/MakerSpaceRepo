import { Controller } from "@hotwired/stimulus";
import timeGridPlugin from "@fullcalendar/timegrid";
import dayGridPlugin from "@fullcalendar/daygrid";
import interactionPlugin from "@fullcalendar/interaction";

import { closeSaved } from "../src/calendar_dialog.js";
import { pageCalendar } from "../src/page_calendar.js";
import { editableUnavailability } from "../src/unavailability_event.js";

// The hosts listed in the failed-calendars header: a JSON list of strings and
// nulls, or nothing for a missing, malformed or differently shaped header.
function failedHosts(header) {
  try {
    const hosts = JSON.parse(header);
    const valid =
      Array.isArray(hosts) &&
      hosts.every((host) => host === null || typeof host === "string");
    return valid ? hosts : [];
  } catch {
    return [];
  }
}

// Stimulus defines the target, value and outlet accessors at runtime; this
// tells the type checker.
const TypedController = /** @type {new () => Controller<HTMLElement> & {
  calendarTarget: HTMLElement,
  containerTarget: HTMLElement,
  spinnerTarget: HTMLElement,
  failuresTarget: HTMLElement,
  failureTemplateValue: string,
  unknownHostValue: string,
  feedFailureValue: string,
  feedUrlValue: string,
  unavailabilityFormOutlet: { element: HTMLElement, openForAdd(options?: { returnFocusTo?: HTMLElement }): void, openForEdit(event: any): void, openForRange(range: { start: string, end: string }): void },
  importedEventDetailsOutlet: { show(event: any, returnFocusTo?: HTMLElement | null): void },
}} */ (/** @type {unknown} */ (Controller));

// The staff member's own unavailabilities: draws a FullCalendar on the
// calendar target, opens the unavailability dialog (the unavailability-form
// outlet) from it, and removes the calendar when the element leaves the page.
export default class extends TypedController {
  static targets = ["calendar", "container", "spinner", "failures"];
  static values = {
    feedUrl: String,
    failureTemplate: String,
    unknownHost: String,
    feedFailure: String,
  };
  static outlets = ["unavailability-form", "imported-event-details"];

  connect() {
    this.calendar = pageCalendar(this.calendarTarget, this.calendarOptions());
    this.containerTarget.style.display = "block";
    this.spinnerTarget.style.display = "none";
    this.calendar.render();
  }

  disconnect() {
    this.calendar?.destroy();
    this.calendar = null;
  }

  // The dialog saved or deleted: close it and fetch the entries again.
  saved() {
    closeSaved(this.unavailabilityFormOutlet.element);
    this.calendar.refetchEvents();
  }

  addUnavailability(event) {
    this.unavailabilityFormOutlet.openForAdd({
      returnFocusTo: event.currentTarget,
    });
  }

  // Only the staff member's own unavailabilities can be edited; an event
  // imported from a calendar feed opens a read-only view of it instead. The
  // element is the one clicked, which gets the focus back when the view closes.
  openEvent(event, element) {
    if (event.extendedProps?.eventType === "unavailability") {
      this.unavailabilityFormOutlet.openForEdit(editableUnavailability(event));
    } else {
      this.importedEventDetailsOutlet.show(event, element);
    }
  }

  // The feed names, in a header, the hosts of the linked calendars it could
  // not load (a JSON list; a link whose host could not be read is null). Each
  // is listed as text; nothing is listed when all loaded or the header cannot
  // be read, so the events are never held back by it.
  showFailures(response) {
    this.listFailures(
      failedHosts(response.headers.get("X-Failed-Calendars")).map((host) =>
        this.failureTemplateValue.replace(
          "{host}",
          () => host ?? this.unknownHostValue,
        ),
      ),
    );
  }

  // The feed itself could not be loaded, so any earlier lines are out of date.
  showFeedFailure() {
    this.listFailures([this.feedFailureValue]);
  }

  listFailures(lines) {
    this.failuresTarget.replaceChildren(
      ...lines.map((text) => {
        const line = document.createElement("div");
        line.textContent = text;
        return line;
      }),
    );
    this.failuresTarget.hidden = lines.length === 0;
  }

  calendarOptions() {
    return {
      plugins: [timeGridPlugin, dayGridPlugin, interactionPlugin],
      timeZone: "America/Toronto",
      initialView: "timeGridWeek",
      headerToolbar: {
        left: "prev,next,today",
        center: "title",
        right: "timeGridWeek,dayGridMonth",
      },
      scrollTime: "07:00:00",
      selectable: true,
      selectMirror: true,
      selectMinDistance: 30,
      height: "80vh",
      events: {
        url: this.feedUrlValue,
        success: (_events, response) => this.showFailures(response),
        failure: () => this.showFeedFailure(),
      },
      eventClick: (info) => this.openEvent(info.event, info.el),
      select: (info) =>
        this.unavailabilityFormOutlet.openForRange({
          start: info.startStr,
          end: info.endStr,
        }),
      eventDidMount: (info) => this.fadeIn(info),
      initialDate: localStorage.fullCalendarDefaultDateStaffUnavailabilities,
      datesSet: (info) => this.rememberDate(info),
    };
  }

  fadeIn(info) {
    requestAnimationFrame(() => {
      info.el.classList.add("fade-in");
    });
  }

  // recall dates on refresh
  rememberDate(info) {
    const date = new Date(info.view.currentStart);
    localStorage.fullCalendarDefaultDateStaffUnavailabilities =
      date.toISOString();
  }
}
