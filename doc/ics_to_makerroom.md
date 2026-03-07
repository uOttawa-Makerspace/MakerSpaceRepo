Epic By: Valentino Vinod
Start Date: September 1st, 2025 (approximately)
End Date: Nov. 27, 2025 (approximately)

## PURPOSE

CEED staff members often have to manually move their google calendar bookings to Makerroom. This epic attempts to link the two.

## Google Cal to Makerroom

Admin can now go to admin/spaces and (specifically within the CEED Space) paste their desired google calendar link into the staff needed calendars bar. If they select "Send to Makerroom", their bookings will be posted in makerroom under the subspace code indicated in the event "locations"

e.g.

Stem 124: Google booking with Location: STM 124
Stem 126: Google booking with Location: STM 126

Note: These strings are specific to the sub space names in the database and must be adhered to

## Makerroom to Google Cal

When a booking is saved to makerroom, its sub space id is read. If it is in either stem 124 or 124, the booking is automatically posted in the official CEED stem 124 or 126 google cal
NOTE: The ics link hasn't been pasted in yet but there is a comment above the function saying to paste it when ready
Currently, all makerroom events in these two subspaces are only posted to the test calendar.

## Updating events

Currently, if you update events or add new events to your personal calendar, there is no way to represent these in makerroom without going back to the admin area and re-saving your cal.

If you update an existing event or create a new event in makerroom however, CEED's google cal will respond as the two are linked.

## Unit Tests

There is one unit test which tests the parse_ics_calendar function in calendar_helper. It works by reading an ics file stored in spec/support/assets.

## SUMMARY

Essentially, you can use admin area as a "launch point" for your events where it reads your personal calendar and puts them into makerroom. Once that is done, makerroom and CEED's google calendars talk to each other freely.
