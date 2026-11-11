import { Controller } from "@hotwired/stimulus";
import { Calendar } from "@fullcalendar/core";
import rrulePlugin from "@fullcalendar/rrule";
import timeGridPlugin from "@fullcalendar/timegrid";
import dayGridPlugin from "@fullcalendar/daygrid";
import interactionPlugin from "@fullcalendar/interaction";

import { makeCalendarAccessible } from "../src/calendar_accessibility.js";
import {
  addUnavailabilityClick,
  eventClick,
  eventCreate,
} from "../src/unavailabilities_helpers.js";

// Stimulus defines the target accessors at runtime; this tells the type checker.
const TypedController = /** @type {new () => Controller<HTMLElement> & {
  calendarTarget: HTMLElement,
  containerTarget: HTMLElement,
  spinnerTarget: HTMLElement,
}} */ (/** @type {unknown} */ (Controller));

// The staff member's own unavailabilities: draws a FullCalendar on the
// calendar target, opens the unavailability dialog from it, and removes the
// calendar when the element leaves the page.
export default class extends TypedController {
  static targets = ["calendar", "container", "spinner"];

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

  // The add button opens the dialog through its Bootstrap data attributes;
  // this puts the dialog in add mode first.
  addUnavailability() {
    addUnavailabilityClick();
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
      events: "/staff/unavailabilities/json",
      eventClick: (info) => eventClick(info.event),
      select: (info) => eventCreate(info),
      viewDidMount: () => makeCalendarAccessible(this.calendarTarget),
      eventDidMount: (info) => {
        // fade in event
        requestAnimationFrame(() => {
          info.el.classList.add("fade-in");
        });
      },
      initialDate: localStorage.fullCalendarDefaultDateStaffUnavailabilities,
      datesSet: (info) => {
        // recall dates on refresh
        const date = new Date(info.view.currentStart);
        localStorage.fullCalendarDefaultDateStaffUnavailabilities =
          date.toISOString();
      },
    };
  }
}
