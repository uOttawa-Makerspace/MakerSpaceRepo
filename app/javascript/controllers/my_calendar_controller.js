import { Controller } from "@hotwired/stimulus";
import { Calendar } from "@fullcalendar/core";
import rrulePlugin from "@fullcalendar/rrule";
import timeGridPlugin from "@fullcalendar/timegrid";
import dayGridPlugin from "@fullcalendar/daygrid";
import { Tooltip } from "bootstrap";

import { applyEventBackground } from "../src/calendar_background.js";

// The title and description are free text, so they go in as text nodes and
// never as markup.
function tooltipContent(title, description) {
  const content = document.createElement("span");
  content.append(title);
  if (description) {
    const note = document.createElement("i");
    note.textContent = description;
    content.append(document.createElement("br"), note);
  }
  return content;
}

// The staff work calendar: draws a FullCalendar of the shifts, trainings and
// meetings in the feed of the user's space on the calendar target, and removes
// it when the element leaves the page.
export default class extends Controller {
  static targets = ["calendar", "container", "spinner"];
  static values = { feedUrl: String };

  connect() {
    this.onlyShowMyShifts = false;

    // A page restored from Turbo's cache still holds the markup of the
    // calendar that was drawn before, so start from an empty element.
    this.ui.calendarTarget.replaceChildren();
    this.calendar = new Calendar(
      this.ui.calendarTarget,
      this.calendarOptions(),
    );

    this.ui.containerTarget.style.display = "block";
    this.ui.spinnerTarget.style.display = "none";
    this.calendar.render();
    this.labelOverlapButton();
  }

  disconnect() {
    this.calendar?.destroy();
    this.calendar = null;
  }

  // Stimulus defines the target and value accessors at runtime; the cast tells
  // the type checker.
  get ui() {
    return /** @type {any} */ (this);
  }

  calendarOptions() {
    return {
      plugins: [timeGridPlugin, dayGridPlugin, rrulePlugin],
      timeZone: "America/Toronto",
      initialView: "timeGridWeek",
      headerToolbar: {
        left: "prev,next,today toggleOthersShifts toggleEventOverlap",
        center: "title",
        right: "timeGridWeek,dayGridMonth",
      },
      slotEventOverlap: localStorage.fullCalendarEventOverlap === "true",
      customButtons: {
        toggleOthersShifts: {
          text: "Show My Shifts Only",
          click: () => this.toggleOthersShifts(),
        },
        toggleEventOverlap: {
          text: "",
          click: () => this.toggleEventOverlap(),
        },
      },
      scrollTime: "07:00:00",
      height: "80vh",
      events: this.ui.feedUrlValue,
      eventDidMount: (info) => this.decorateEvent(info),
      eventWillUnmount: (info) => Tooltip.getInstance(info.el)?.dispose(),
      initialDate: localStorage.fullCalendarDefaultDateStaffCalendar,
      datesSet: (info) => {
        // recall dates on refresh
        const date = new Date(info.view.currentStart);
        localStorage.fullCalendarDefaultDateStaffCalendar = date.toISOString();
      },
    };
  }

  toggleOthersShifts() {
    this.onlyShowMyShifts = !this.onlyShowMyShifts;

    this.calendar.getEvents().forEach((event) => {
      const mine = event.extendedProps.hasCurrentUser;
      event.setProp(
        "display",
        this.onlyShowMyShifts && !mine ? "none" : "auto",
      );
    });

    this.buttonNamed("toggleOthersShifts").innerHTML = this.onlyShowMyShifts
      ? "Show All Shifts"
      : "Show My Shifts Only";
  }

  toggleEventOverlap() {
    const overlap = !this.calendar.getOption("slotEventOverlap");
    localStorage.fullCalendarEventOverlap = overlap;
    this.calendar.setOption("slotEventOverlap", overlap);
    this.labelOverlapButton();
  }

  labelOverlapButton() {
    this.buttonNamed("toggleEventOverlap").innerHTML = this.calendar.getOption(
      "slotEventOverlap",
    )
      ? "Disable Event Overlap"
      : "Enable Event Overlap";
  }

  buttonNamed(name) {
    return this.element.querySelector(`.fc-${name}-button`);
  }

  decorateEvent(info) {
    // fade in event
    requestAnimationFrame(() => {
      info.el.classList.add("fade-in");
    });

    new Tooltip(info.el, {
      title: tooltipContent(
        info.event.title,
        info.event.extendedProps.description,
      ),
      html: true,
    });

    // add user color bg gradient
    applyEventBackground(info.el, info.event.extendedProps.background);
  }
}
