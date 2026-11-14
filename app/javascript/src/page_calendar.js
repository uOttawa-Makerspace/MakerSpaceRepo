import { Calendar } from "@fullcalendar/core";
import dayGridPlugin from "@fullcalendar/daygrid";
import timeGridPlugin from "@fullcalendar/timegrid";
import frenchLocale from "@fullcalendar/core/locales/fr-ca";

import { makeCalendarAccessible } from "./calendar_accessibility.js";

// A FullCalendar on the target with the time and day grid plugins (and any
// given), from the settings the calendars share, which the options may change.
// It is always in the page's language (every layout names one), so its buttons
// and their accessible names are French on a French page, and this
// viewDidMount, which hides the toolbar chevrons from assistive technology,
// replaces any in the options. The target is emptied first: a page restored
// from Turbo's cache still holds the calendar drawn before.
export function pageCalendar(target, options, ...plugins) {
  target.replaceChildren();
  return new Calendar(target, {
    timeZone: "America/Toronto",
    firstDay: 0,
    height: "80vh",
    scrollTime: "07:00:00",
    ...options,
    plugins: [timeGridPlugin, dayGridPlugin, ...plugins],
    locales: [frenchLocale],
    locale: target.ownerDocument.documentElement.lang,
    viewDidMount: makeCalendarAccessible.bind(null, target),
  });
}
