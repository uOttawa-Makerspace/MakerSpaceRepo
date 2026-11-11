import { Controller } from "@hotwired/stimulus";
import { Calendar } from "@fullcalendar/core";
import rrulePlugin from "@fullcalendar/rrule";
import timeGridPlugin from "@fullcalendar/timegrid";
import dayGridPlugin from "@fullcalendar/daygrid";
import interactionPlugin from "@fullcalendar/interaction";

import { makeCalendarAccessible } from "../src/calendar_accessibility.js";

// Stimulus defines the target, value and outlet accessors at runtime; this
// tells the type checker.
const TypedController = /** @type {new () => Controller<HTMLElement> & {
  calendarTarget: HTMLElement,
  containerTarget: HTMLElement,
  spinnerTarget: HTMLElement,
  feedUrlValue: string,
  unavailabilityFormOutlet: { openForAdd(options?: { returnFocusTo?: HTMLElement }): void, openForEdit(event: any): void, openForRange(range: { start: string, end: string }): void },
}} */ (/** @type {unknown} */ (Controller));

// The staff member's own unavailabilities: draws a FullCalendar on the
// calendar target, opens the unavailability dialog (the unavailability-form
// outlet) from it, and removes the calendar when the element leaves the page.
export default class extends TypedController {
  static targets = ["calendar", "container", "spinner"];
  static values = { feedUrl: String };
  static outlets = ["unavailability-form"];

  connect() {
    // A page restored from Turbo's cache still holds the markup of the
    // calendar that was drawn before, so start from an empty element.
    this.calendarTarget.replaceChildren();
    this.calendar = new Calendar(this.calendarTarget, this.calendarOptions());

    this.containerTarget.style.display = "block";
    this.spinnerTarget.style.display = "none";
    this.calendar.render();
  }

  disconnect() {
    this.calendar?.destroy();
    this.calendar = null;
  }

  addUnavailability(event) {
    this.unavailabilityFormOutlet.openForAdd({
      returnFocusTo: event.currentTarget,
    });
  }

  // Only the staff member's own unavailabilities can be edited; an event
  // imported from a calendar feed is shown but does nothing when clicked.
  editOwn(event) {
    if (event.extendedProps?.eventType !== "unavailability") return;
    this.unavailabilityFormOutlet.openForEdit(event);
  }

  calendarOptions() {
    return {
      plugins: [timeGridPlugin, dayGridPlugin, rrulePlugin, interactionPlugin],
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
      events: this.feedUrlValue,
      eventClick: (info) => this.editOwn(info.event),
      select: (info) =>
        this.unavailabilityFormOutlet.openForRange({
          start: info.startStr,
          end: info.endStr,
        }),
      viewDidMount: () => makeCalendarAccessible(this.calendarTarget),
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
