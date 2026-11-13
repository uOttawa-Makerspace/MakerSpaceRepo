import { Controller } from "@hotwired/stimulus";
import { Calendar } from "@fullcalendar/core";
import dayGridPlugin from "@fullcalendar/daygrid";
import timeGridPlugin from "@fullcalendar/timegrid";

import { makeCalendarAccessible } from "../src/calendar_accessibility.js";
import { rangeSource, unticked } from "../src/range_source.js";

// Below this width the calendar shows fewer days.
const NARROW_WIDTH = 1000;

// Stimulus defines the target and value accessors at runtime; this tells the
// type checker.
const TypedController = /** @type {new () => Controller<HTMLElement> & {
  calendarTarget: HTMLElement,
  filterTargets: HTMLInputElement[],
  hasFilterTarget: boolean,
  feedUrlValue: string,
  weekValue: boolean,
}} */ (/** @type {unknown} */ (Controller));

// The opening hours of the spaces: the hours the server sends for the days
// shown, with a checkbox per space (from the server) that hides or shows its
// hours. The hours page shows a week and an all-day row, the home page fewer
// days; a narrow window shows fewer again. With no space there is no calendar
// (the server says so in its place).
export default class extends TypedController {
  static targets = ["calendar", "filter"];
  static values = { feedUrl: String, week: Boolean };

  connect() {
    if (!this.hasFilterTarget) return;
    this.filterTargets.forEach((box) => {
      box.style.backgroundColor = box.dataset.color;
      box.style.borderColor = box.dataset.color;
    });
    // A page restored from Turbo's cache still holds the calendar drawn before.
    this.calendarTarget.replaceChildren();
    this.calendar = new Calendar(this.calendarTarget, this.calendarOptions());
    this.calendar.render();
  }

  disconnect() {
    this.calendar?.destroy();
    this.calendar = null;
  }

  redraw() {
    this.calendar.getEventSourceById("hours").refetch();
  }

  viewForWidth() {
    const narrow = window.innerWidth < NARROW_WIDTH;
    if (this.weekValue) return narrow ? "timeGridThreeDay" : "timeGridSevenDay";
    return narrow ? "timeGridTwoDay" : "timeGridFiveDay";
  }

  fitView() {
    const view = this.viewForWidth();
    if (this.calendar.view.type !== view) this.calendar.changeView(view);
  }

  hoursSource() {
    return rangeSource(
      "hours",
      this.feedUrlValue,
      (calendars) =>
        calendars.flatMap((calendar) =>
          calendar.events.map((row) => ({ ...row, color: calendar.color })),
        ),
      (rows) => {
        const hidden = unticked(this.filterTargets);
        return rows.filter((row) => !hidden.has(row.groupId));
      },
    );
  }

  /** @returns {import("@fullcalendar/core").CalendarOptions} */
  calendarOptions() {
    return {
      plugins: [timeGridPlugin, dayGridPlugin],
      initialView: this.viewForWidth(),
      views: {
        timeGridTwoDay: {
          type: "timeGrid",
          duration: { days: 2 },
          buttonText: "2 day",
        },
        timeGridThreeDay: {
          type: "timeGrid",
          duration: { days: 3 },
          buttonText: "3 day",
        },
        timeGridFiveDay: {
          type: "timeGrid",
          duration: { days: 5 },
          buttonText: "5 day",
        },
        timeGridSevenDay: { type: "timeGridWeek", buttonText: "7 day" },
      },
      firstDay: 0,
      headerToolbar: { left: "prev", center: "title", right: "next" },
      eventSources: [this.hoursSource()],
      expandRows: true,
      contentHeight: "auto",
      stickyHeaderDates: false,
      timeZone: "America/Toronto",
      nowIndicator: true,
      slotEventOverlap: false,
      allDaySlot: this.weekValue,
      slotMinTime: "08:00:00",
      slotMaxTime: "22:00:00",
      slotDuration: "01:00:00",
      slotLabelInterval: "01:00:00",
      eventTimeFormat: {
        hour: "2-digit",
        minute: "2-digit",
        meridiem: "short",
      },
      viewDidMount: () => makeCalendarAccessible(this.calendarTarget),
      windowResize: () => this.fitView(),
    };
  }
}
