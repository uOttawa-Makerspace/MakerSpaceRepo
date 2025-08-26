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
works really. Pray it doesn't break.

## Server architecture

There's two models to know about. `PiReader` represents a tap box in a space.
`Rfid` represents a student card serial number and links it to a user and the
mac adddress of the PI reader.

There's `RfidController` which handles the interface with the student cards. It
handles creating and assigning an RFID scanner with a space. There's two exposed
endpoints:

- `/rfid/get_unset_rfids` shows the most recent five cards that were tapped.
  This list is displayed on the user profile page for staff members to link
  cards. It uses the current user's space to determine which space to show
  recent cards.

- `/rfid/card_number` is a POST endpoint that notifies the server of a user
  tapping their card. It takes a `:space_id` parameter or a `:pi_mac_address`
  parameter, and a `:rfid` card serial number parameter.

Past that, there's some private helper functions used to verify
