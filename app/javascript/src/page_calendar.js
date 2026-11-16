import { Calendar } from "@fullcalendar/core";
import dayGridPlugin from "@fullcalendar/daygrid";
import timeGridPlugin from "@fullcalendar/timegrid";
import frenchLocale from "@fullcalendar/core/locales/fr-ca";

import { makeCalendarAccessible } from "./calendar_accessibility.js";

// The words the page gives its calendar element (calendar_texts_data).
export function calendarTexts(target) {
  return JSON.parse(target.dataset.calendarTexts);
}

// A FullCalendar on the target with the time and day grid plugins (and any
// given), from the settings the calendars share, which the options may change.
// It is in the page's language (every layout names one), with the page's hints,
// so its buttons and their names are French on a French page, and this
// viewDidMount, which hides the toolbar chevrons from assistive technology,
// replaces any in the options. A toolbar may show the shared overlap toggle,
// toggleEventOverlap. The target is emptied first: a page restored from
// Turbo's cache still holds the calendar drawn before.
export function pageCalendar(target, options, ...plugins) {
  target.replaceChildren();
  const texts = calendarTexts(target);
  const toolbar = Object.values(options.headerToolbar ?? {})
    .join(",")
    .split(/[ ,]/);
  const overlap = toolbar.includes("toggleEventOverlap")
    ? overlapToggle(texts, () => calendar)
    : {};
  const calendar = new Calendar(target, {
    timeZone: "America/Toronto",
    firstDay: 0,
    height: "80vh",
    scrollTime: "07:00:00",
    ...texts.hints,
    ...overlap,
    ...options,
    customButtons: { ...overlap.customButtons, ...options.customButtons },
    plugins: [timeGridPlugin, dayGridPlugin, ...plugins],
    locales: [frenchLocale],
    locale: target.ownerDocument.documentElement.lang,
    viewDidMount: makeCalendarAccessible.bind(null, target),
  });
  return calendar;
}

// Gives the calendar's custom button of that name a new label. FullCalendar
// draws it and names the button (its title, the tooltip) after it, also when
// it draws the toolbar again.
export function relabel(calendar, name, label) {
  const buttons = calendar.getOption("customButtons");
  calendar.setOption("customButtons", {
    ...buttons,
    [name]: { ...buttons[name], text: label },
  });
}

// Event overlap in the week grid is one setting for every calendar showing
// its toggle, which the browser remembers: such a calendar starts with it, and
// the button, named for what pressing it does, turns it the other way.
function overlapToggle(texts, calendar) {
  const label = (on) => (on ? texts.disableOverlap : texts.enableOverlap);
  const overlap = localStorage.fullCalendarEventOverlap === "true";
  const click = () => {
    const on = !calendar().getOption("slotEventOverlap");
    localStorage.fullCalendarEventOverlap = on;
    calendar().setOption("slotEventOverlap", on);
    relabel(calendar(), "toggleEventOverlap", label(on));
  };
  return {
    slotEventOverlap: overlap,
    customButtons: { toggleEventOverlap: { text: label(overlap), click } },
  };
}
