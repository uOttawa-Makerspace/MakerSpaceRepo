import { Calendar } from "@fullcalendar/core";
import frenchLocale from "@fullcalendar/core/locales/fr-ca";

import { makeCalendarAccessible } from "./calendar_accessibility.js";

// A FullCalendar on the target, in the language the page names (every layout
// names one): its own words (the toolbar buttons and the names assistive
// technology reads for them, dates, times) are French on a French page, and
// its toolbar chevrons are hidden from assistive technology after each view is
// drawn. A page restored from Turbo's cache still holds the calendar drawn
// before, so the target is emptied first.
/**
 * @param {HTMLElement} target
 * @param {import("@fullcalendar/core").CalendarOptions} options
 */
export function pageCalendar(target, options) {
  target.replaceChildren();
  return new Calendar(target, {
    ...options,
    locales: [frenchLocale],
    locale: target.ownerDocument.documentElement.lang,
    viewDidMount: makeCalendarAccessible.bind(null, target),
  });
}
