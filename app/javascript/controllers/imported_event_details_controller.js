import { Controller } from "@hotwired/stimulus";
import { Modal } from "bootstrap";

import { wallFromCalendar } from "../src/recurrence.js";

const DAY_MS = 24 * 60 * 60 * 1000;

// Stimulus defines the target and value accessors at runtime; this tells the
// type checker.
const TypedController = /** @type {new () => Controller<HTMLElement> & {
  titleTarget: HTMLElement,
  timeTarget: HTMLElement,
  descriptionTarget: HTMLElement,
  sourceTarget: HTMLElement,
  fromValue: string,
  allDayValue: string,
}} */ (/** @type {unknown} */ (Controller));

// A read-only dialog for an event imported from a linked calendar. The
// calendar's own events can be edited; these cannot, so the dialog shows what
// the event holds and the page's explanation. Everything is written as text,
// and it only touches its own element.
export default class extends TypedController {
  static targets = ["title", "time", "description", "source"];
  static values = { from: String, allDay: String };

  // The event is the calendar's: its title, Toronto-time start and end
  // strings, all-day flag, and the link host and description it carries.
  // The element given as returnFocusTo gets the focus back when the dialog
  // closes.
  show(calendarEvent, returnFocusTo = null) {
    const { sourceHost = "", description = "" } =
      calendarEvent.extendedProps || {};
    this.returnFocusTo = returnFocusTo;

    this.titleTarget.textContent = calendarEvent.title;
    this.timeTarget.textContent = this.timeText(calendarEvent);
    this.descriptionTarget.textContent = description || "";
    this.descriptionTarget.hidden = !description;
    this.sourceTarget.textContent = this.fromValue.replace(
      "{host}",
      sourceHost || "",
    );

    Modal.getOrCreateInstance(this.element).show();
  }

  returnFocus() {
    this.returnFocusTo?.focus();
    this.returnFocusTo = null;
  }

  timeText({ startStr, endStr, allDay }) {
    const start = wallFromCalendar(startStr);
    if (allDay) return this.allDayText(start, endStr);
    const end = endStr ? wallFromCalendar(endStr) : start;
    return this.timedText(start, end);
  }

  // An all-day event's end is the day after its last day.
  allDayText(start, endStr) {
    const last = endStr ? wallFromCalendar(endStr) - DAY_MS : start;
    const days =
      last > start
        ? `${this.dateText(start)} – ${this.dateText(last)}`
        : this.dateText(start);
    return `${days} · ${this.allDayValue}`;
  }

  timedText(start, end) {
    const from = this.dateTimeText(start);
    if (end === start) return from;
    const sameDay = this.dateText(start) === this.dateText(end);
    return `${from} – ${sameDay ? this.clockText(end) : this.dateTimeText(end)}`;
  }

  // The wall times count as UTC (see recurrence.js), so they are formatted in
  // UTC.
  dateText(wall) {
    return this.format(wall, { dateStyle: "medium" });
  }

  clockText(wall) {
    return this.format(wall, { timeStyle: "short" });
  }

  dateTimeText(wall) {
    return this.format(wall, { dateStyle: "medium", timeStyle: "short" });
  }

  format(wall, options) {
    const locale = this.element.ownerDocument.documentElement.lang || "en";
    return new Intl.DateTimeFormat(locale, {
      timeZone: "UTC",
      ...options,
    }).format(wall);
  }
}
