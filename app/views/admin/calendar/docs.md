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
