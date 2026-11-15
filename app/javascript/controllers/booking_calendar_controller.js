import { Controller } from "@hotwired/stimulus";
import interactionPlugin from "@fullcalendar/interaction";
import listPlugin from "@fullcalendar/list";

import { calendarTexts, pageCalendar } from "../src/page_calendar.js";
import { serverError } from "../src/request_error";

/** @typedef {{ startStr: string, endStr: string }} Range */

// Stimulus defines the outlet accessors at runtime; this tells the type checker.
const TypedController = /** @type {new () => Controller<HTMLElement> & {
  bookingModalOutlet: { openNew(range?: Range): void, openBooking(event: any): void },
  bookingToastOutlet: { text(name: string): string, show(titleName: string, text: string): void },
}} */ (/** @type {unknown} */ (Controller));

// The day the address names (start=2026-03-02), or today when it names none
// or no real day.
function firstDay(params) {
  const day = new Date(params.get("start") ?? NaN);
  return isNaN(day.getTime()) ? new Date() : day;
}

// A week of a room's bookings (the room and the first day come from the
// address). Selecting a range or pressing Book opens the booking modal for a
// new booking, and clicking a booking opens it there.
export default class extends TypedController {
  static outlets = ["booking-modal", "booking-toast"];

  connect() {
    this.calendar = pageCalendar(
      this.element,
      this.calendarOptions(new URLSearchParams(window.location.search)),
      interactionPlugin,
      listPlugin,
    );
    this.calendar.render();
  }

  disconnect() {
    this.calendar?.destroy();
    this.calendar = null;
  }

  // Draws the room's bookings again, after the modal saved one.
  refetch() {
    this.calendar.refetchEvents();
  }

  // The calendar feed failed: show the server's reason when it sent one.
  /** @param {any} error */
  async showFeedError(error) {
    const body = await error?.response?.json?.().catch(() => null);
    if (!this.element.isConnected) return; // the user went on to another page
    const toast = this.bookingToastOutlet;
    toast.show("failedTitle", serverError(body, toast.text("feed")));
  }

  /** @param {URLSearchParams} params @returns {import("@fullcalendar/core").CalendarOptions} */
  calendarOptions(params) {
    const modal = () => this.bookingModalOutlet;
    return {
      initialDate: firstDay(params),
      height: "auto",
      headerToolbar: {
        left: "prev,today,next",
        center: "",
        right: "book,timeGridWeek",
      },
      customButtons: {
        book: {
          text: calendarTexts(this.element).book,
          click: () => modal().openNew(),
        },
      },
      views: {
        timeGridWeek: {
          dayHeaderFormat: { weekday: "short", day: "numeric", month: "short" },
        },
      },
      allDaySlot: false,
      initialView: "timeGridWeek",
      navLinks: true,
      slotEventOverlap: false,
      slotMinTime: "06:00:00",
      slotMaxTime: "22:00:00",
      selectable: true,
      eventTimeFormat: { hour: "2-digit", minute: "2-digit", hour12: false },
      dayMaxEvents: true,
      eventSources: [
        {
          id: "booked",
          url: `/sub_space_booking/bookings?room=${encodeURIComponent(params.get("room"))}`,
          failure: (error) => this.showFeedError(error),
        },
      ],
      select: (range) => modal().openNew(range),
      eventClick: (arg) => modal().openBooking(arg.event),
    };
  }
}
