import { Controller } from "@hotwired/stimulus";
import { Tooltip } from "bootstrap";

import { applyEventBackground } from "../src/calendar_background.js";
import { calendarTexts, pageCalendar, relabel } from "../src/page_calendar.js";

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

// Stimulus defines the target and value accessors at runtime; this tells the
// type checker.
const TypedController = /** @type {new () => Controller<HTMLElement> & {
  calendarTarget: HTMLElement,
  containerTarget: HTMLElement,
  spinnerTarget: HTMLElement,
  feedUrlValue: string,
}} */ (/** @type {unknown} */ (Controller));

// The staff work calendar: draws a FullCalendar of the shifts, trainings and
// meetings in the feed of the user's space on the calendar target, and removes
// it when the element leaves the page.
export default class extends TypedController {
  static targets = ["calendar", "container", "spinner"];
  static values = { feedUrl: String };

  connect() {
    this.onlyShowMyShifts = false;
    this.texts = calendarTexts(this.calendarTarget);
    this.calendar = pageCalendar(this.calendarTarget, this.calendarOptions());
    this.containerTarget.style.display = "block";
    this.spinnerTarget.style.display = "none";
    this.calendar.render();
  }

  disconnect() {
    this.calendar?.destroy();
    this.calendar = null;
  }

  calendarOptions() {
    const overlap = localStorage.fullCalendarEventOverlap === "true";
    return {
      initialView: "timeGridWeek",
      headerToolbar: {
        left: "prev,next,today toggleOthersShifts toggleEventOverlap",
        center: "title",
        right: "timeGridWeek,dayGridMonth",
      },
      slotEventOverlap: overlap,
      customButtons: {
        toggleOthersShifts: {
          text: this.texts.showMyShiftsOnly,
          click: () => this.toggleOthersShifts(),
        },
        toggleEventOverlap: {
          text: this.overlapLabel(overlap),
          click: () => this.toggleEventOverlap(),
        },
      },
      events: this.feedUrlValue,
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

    relabel(
      this.calendar,
      "toggleOthersShifts",
      this.onlyShowMyShifts
        ? this.texts.showAllShifts
        : this.texts.showMyShiftsOnly,
    );
  }

  toggleEventOverlap() {
    const overlap = !this.calendar.getOption("slotEventOverlap");
    localStorage.fullCalendarEventOverlap = overlap;
    this.calendar.setOption("slotEventOverlap", overlap);
    relabel(this.calendar, "toggleEventOverlap", this.overlapLabel(overlap));
  }

  overlapLabel(overlap) {
    return overlap ? this.texts.disableOverlap : this.texts.enableOverlap;
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
