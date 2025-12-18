# Work Calendar Docs

## Nomenclature

- Events: a catch-all term for shifts, trainings, meetings, and other blocks of time scheduled by admins
- Unavailabilities: blocks of dates/times when staff are unable to work
- Recurrence rule/RRule: a string or object used to describe an event that recurs (daily, weekly, etc.) including the dates to exclude (EXDATES) and the eventual end date (UNTIL)

## User-Facing Pages

### Staff

- `/staff/unavailabilities` - Staff can view, create, edit, and import ICS URLs with their work unavailabilities.
- `/staff/my_calendar` - Staff can choose a space (MTC, Makerspace, etc.) and view their events

### Admin

- `/admin/calendar` - Admins can choose a space, view imported calendars for that space (open hours, etc.), view staff unavailabilities, and create/edit events for the space. Essentially, an all-in-one scheduling and staff work management calendar

## Inner Workings

Both `/staff/unavailabilities` and `/admin/calendar` have a few main JS files that provide functionality.

1. **The controller file** initializes the event listeners, namely for the "Add Event"/"Add Unavailability" buttons.
2. **fullcalendar_setup_xxx.js** initializes and configures Full Calendar and captures events and event sources to be displayed on the calendar, as well as handle the checkboxes and event visibility functionality for admins
3. **calendar_helper.js** has calendar helper functions and also admin functions for various callbacks like when events are clicked (subsequently, handles update and delete button form actions)
4. **unavailabilities_helper.js** has the same callback helpers as previous, except for the unavailabilities page
5. **manage_calendar_events.js** and **manage_unavailabilities.js** contain similar functionality that handles the create modal and everything that comes with it (RRule building, TomSelect for staff selecting based on their unavailabilities, etc.)

The `staff/my_calendar` page is super simple, fetching the events JSON and displaying it so everything is contained in the controller JS file.

## Caveats and Gotchas

TLDR: everything broken has to do with `isUnavailableDuring()` inside `manage_calendar_events.js` unavailability calculations are off by 1 hour when recurring staff unavails are created in previous timezone offset (DST/ST) and when recurring staff unavails start late enough that in UTC they are the next day. an attempted fix can be found in #2d9411c which may be worth referencing but didn't work enough so I resorted back to using UTC for the calculation.

### 1. DTSTART, EXDATES, RDATES, EXRULES

DTSTART is a date time string of the beginning of a recurring event.

EXDATES are for excluded dates in recurring events. For example, since there are no classes during reading week, deleting them in your calendar would create EXDATES.

RDATES and EXRULES hopefully we never run into. Google Calendar (and other iCal sources) have different ways of telling us a recurring event has been rescheduled (say Makerspace has longer open hours before Design Day), which we handle by checking duplicate event IDs.

In the iCal parser, we set DTSTART and EXDATE explicitly to Toronto time and keep it as a floating date (since we will forever use America/Toronto time in FullCalendar, etc.).

### 2. Unavailabilities

Given the floating dates that are in Toronto time already, it is brutal to try to check the unavailabilities of events that have been recurring for months. Putting the recurring events back into UTC (because rrule.js doesn't like TZs) screws a couple things. **Namely, events after 9/10pm which in UTC are the next day (GMT-4 or GMT-5) and mess up recurring events with a BYDAY (that would now be the wrong day). As well, events created in GMT-4 that recur and are now being checked against a day in GMT-5, we have off-by-one hour problems.**

TLDR: unavailabilty checking works except for _certain_ recurring events

### 3. iCal Hmms

For some unknown reason (to me at least), some recurring events made in Google Calendar are sent/parsed (I haven't thoroughly tested as no problems came of it) as a bunch of single events. It makes the returned JSON long but otherwise doesn't seem to cause any issues.
