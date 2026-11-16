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
    return {
      initialView: "timeGridWeek",
      headerToolbar: {
        left: "prev,next,today toggleOthersShifts toggleEventOverlap",
        center: "title",
        right: "timeGridWeek,dayGridMonth",
      },
      customButtons: {
        toggleOthersShifts: {
          text: this.texts.showMyShiftsOnly,
          click: () => this.toggleOthersShifts(),
        },
      },
      events: this.feedUrlValue,
      eventDidMount: (info) => this.decorateEvent(info),
      eventWillUnmount: (info) => Tooltip.getInstance(info.el)?.dispose(),
      initialDate: localStorage.fullCalendarDefaultDateStaffCalendar,
      // the week shown, for the next visit
      datesSet: ({ view }) => {
        localStorage.fullCalendarDefaultDateStaffCalendar =
          view.currentStart.toISOString();
      },
    };
  }

  // Hides the other people's shifts, or shows them all again.
  toggleOthersShifts() {
    const only = (this.onlyShowMyShifts = !this.onlyShowMyShifts);
    this.calendar.getEvents().forEach((event) => {
      const hide = only && !event.extendedProps.hasCurrentUser;
      event.setProp("display", hide ? "none" : "auto");
    });
    const { showAllShifts, showMyShiftsOnly } = this.texts;
    relabel(
      this.calendar,
      "toggleOthersShifts",
      only ? showAllShifts : showMyShiftsOnly,
    );
  }

  // Fades the event in, gives it a tooltip and the staff colours.
  decorateEvent(info) {
    requestAnimationFrame(() => info.el.classList.add("fade-in"));
    new Tooltip(info.el, {
      title: tooltipContent(
        info.event.title,
        info.event.extendedProps.description,
      ),
      html: true,
    });
    applyEventBackground(info.el, info.event.extendedProps.background);
  }
}
