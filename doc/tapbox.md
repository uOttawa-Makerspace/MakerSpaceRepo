# RFID Tab boxes

Users can sign in and sign out of a space by tapping their student cards onto a
tap box in each space. Because the student cards are encrypted and the linking
information isn't readily accessible to us, we collect the serial number and
send that to the `RfidController` instead. Staff members then manually link
cards with user accounts.

This controller has been around since 2015, so if something feels off about it
then you're probably right. There's a lot of global variables in here, such as
using the current user's signed-in space instead of taking a space id.

## Hardware

The firmware is somewhere on makerepo, and I honestly have no clue how that
works really. It used to be a Pi, then an arduino, and now it's an ESP32. Pray
it doesn't break.

## Server architecture

There's two models to know about. `PiReader` represents a tap box in a space.
`Rfid` represents a student card serial number and links it to a user and the
mac adddress of the PI reader.

There's `RfidController` which handles the interface with the student cards. It
handles creating and assigning an RFID scanner with a space. There are two
exposed endpoints:

- `/rfid/get_unset_rfids` shows the most recent five cards that were tapped.
  This list is displayed on the user profile page for staff members to link
  cards. It uses the current user's space to determine which space to show
  recent cards.

- `/rfid/card_number` is a POST endpoint that notifies the server of a user
  tapping their card. It has two callers and no CSRF token is needed (JSON,
  not cookie-authenticated for readers):

  - **Tap boxes (frozen firmware).** JSON `{"rfid": "<card serial>", "mac_address": "<reader mac>"}`
    with no credentials. Accepted only if `mac_address` belongs to a `PiReader`
    that an admin registered **and associated with a space**. The reader's
    space decides where the tap lands (any `space_id` they send is ignored).
    Taps from anything else (unknown MAC, a reader row with no space, no MAC)
    get `401 {"error":"Unauthorized"}`; no reader, card or session is created and
    the only trace is one bounded `Unregistered reader seen` warning per MAC per
    hour (not broadcast to the console). The firmware reads
    only `success`: `"RFID sign in"`, `"RFID sign out"`, or anything else
    (treated as an error).
  - **The React app.** A staff/admin session or `Authorization: Bearer <JWT>`
    with `{"rfid": ..., "space_id": ...}`. It reads only the status code and
    `success` (`"RFID sign out"` means signed out, other truthy means signed in).
    A signed-in non-staff user gets `401`.

  Responses: `200 {"success":"RFID sign in"|"RFID sign out"}` on a tap of a
  card linked to a user (no membership or consent data is returned). Errors are
  never 200: `401` unauthorized, `422` for a new/unlinked card
  (`{"new_rfid":"Temporary RFID created"}`, `{"error":"Temporary RFID already exists"}`),
  missing/invalid `rfid` or no resolvable space, `429 {"error":"Too many requests"}`
  when rate limited.

  MAC addresses are matched case-insensitively and `-` equals `:`; new readers
  are stored as lower-case `aa:bb:cc:dd:ee:ff`.

  Rate limits (per minute): 60 per (reader MAC + source IP) or per staff user,
  600 per source IP, and 10 *rejected* (401) taps per source IP.

Past that, there are some private helper functions used to prevent duplicate
sessions and sign out of old sessions.

Tapping in a space also checks if you're eligible for a membership. See the
membership documentation for more information on how the membership system
works.

To simulate my card tapping in and out of the makerspace:

```
# as a registered reader
curl localhost:3000/rfid/card_number --request POST -H "Content-Type: application/json" --data '{"mac_address": "aa:bb:cc:dd:ee:ff", "rfid": "047AA39A841590"}'
# as staff (JWT from POST /login_authentication.json)
curl localhost:3000/rfid/card_number --request POST -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" --data '{"space_id": 16, "rfid": "047AA39A841590"}'
```

## Operation

When a RFID card taps on a registered tapbox (or a staff member taps), the
controller checks to see if there is already an RFID record present. If not, it creates a \__temporary rfid_, which is
an RFID record with a null user reference and a record of which mac address it
was last seen at. These _temporary rfid_ records are later collected and
displayed at `/rfid/get_unset_rfids`.

If an RFID record already exists with a linked user, it instead signs the user
in or out of a space. Users can tap into a space to sign in, and tap out at the
same space to sign out. They can tap into a different space to sign out of
previous sessions and create a new session in the new space.

## Access notes

- A tap box identifies itself by its registered MAC address (the firmware cannot
  send a secret). Taps are rate limited per reader and per source address, and
  every tap is recorded in `TapBoxLog`.
- ActionCable (staff dashboard modals, tap box console) identifies the user from
  the session cookie and rejects everyone else; `space_event_<id>` is staff only.
