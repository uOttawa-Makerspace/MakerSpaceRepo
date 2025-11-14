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
  tapping their card. It takes a `:space_id` parameter or a `:pi_mac_address`
  parameter, and a `:rfid` card serial number parameter.

Past that, there are some private helper functions used to prevent duplicate
sessions and sign out of old sessions.

Tapping in a space also checks if you're eligible for a membership. See the
membership documentation for more information on how the membership system
works.

To simulate my card tapping in and out of the makerspace:

```
curl localhost:3000/rfid/card_number --request POST -H "Content-Type: application/json" --data '{"space_id": 16, "rfid": "047AA39A841590"}'
```

## Operation

When a RFID card taps on a tapbox, the controller checks to see if the is
already an RFID record present. If not, it creates a \__temporary rfid_, which is
an RFID record with a null user reference and a record of which mac address it
was last seen at. These _temporary rfid_ records are later collected and
displayed at `/rfid/get_unset_rfids`.

If an RFID record already exists with a linked user, it instead signs the user
in or out of a space. Users can tap into a space to sign in, and tap out at the
same space to sign out. They can tap into a different space to sign out of
previous sessions and create a new session in the new space.
