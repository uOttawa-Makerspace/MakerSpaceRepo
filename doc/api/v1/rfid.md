# RFID API

Student-card taps, linking cards to users, and the phone NFC tap. Replaces `GET /rfid/get_unset_rfids`, `PUT /staff_dashboard/link_rfid`, `PUT /staff_dashboard/unlink_rfid` and (for the React app) `POST /rfid/card_number`. Conventions and error format: `README.md`. All endpoints need `Authorization: Bearer <access_token>` and a staff or admin account (S). Pi card readers keep using the legacy device endpoint (`POST /rfid/card_number` with a registered `mac_address`); it is not part of `/api/v1`.

## GET /api/v1/rfid_cards?linked=false
Unlinked cards that were tapped on a reader of the caller's assigned space (readers of every space when none is assigned), most recently tapped first, at most 5: the set `get_unset_rfids` returns. Only `linked=false` is supported.

200:
```json
[ { "card_number": "04A1B2C3", "tapped_at": "2026-10-29T14:03:11Z" } ]
```
`tapped_at` is ISO 8601 UTC (the legacy endpoint sent a ready-made "Tapped at <space> 5 minutes ago" sentence; format it client-side). Cards tapped on a phone have no reader and never appear.

| Status | `error.code` | When |
|---|---|---|
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |
| 422 | `validation_failed` | `linked` missing or not `false` (`fields.linked`) |

## PUT /api/v1/users/:id/rfid
Request: `{ "card_number": "04A1B2C3" }`. Links a card that was tapped earlier (it is in the list above) to the user. `:id` is the numeric user id.

204, empty body. Linking the card to the user who already holds it is a no-op 204. The card's other fields are untouched.

Refused with 422 and nothing changed (legacy did both silently):
- the card belongs to another user (`fields.card_number: ["is already linked to another user"]`): unlink it first;
- the user already holds a different card (`["user already has a card; unlink it first"]`).

| Status | `error.code` | When |
|---|---|---|
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |
| 404 | `not_found` | Unknown, soft-deleted or non-numeric user; card number never tapped (legacy: 500) |
| 422 | `parameter_missing` | `card_number` absent |
| 422 | `validation_failed` | `card_number` not a string, or one of the two refusals above |

## DELETE /api/v1/users/:id/rfid
Unlinks the user's card. As `unlink_rfid` does, the card is re-homed so it shows up in the unlinked list: its `mac_address` becomes the first reader of the space of the caller's last lab session (kept unchanged when the caller has never signed in, or that space has no reader).

204, empty body. A user with no card is a no-op 204 (legacy: 500 for an unknown card number).

| Status | `error.code` | When |
|---|---|---|
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |
| 404 | `not_found` | Unknown, soft-deleted or non-numeric user |

## POST /api/v1/rfid_taps
The phone NFC tap. Request: `{ "card_number": "04A1B2C3", "space_id": 3 }`. Toggles the card owner's presence in that space with the same logic as the Pi readers: not signed in anywhere, sign in (and queue the faculty-membership check and the staff live-update); signed in at this space, sign out; signed in elsewhere, sign out there and in here. The tap is logged. Pi readers cannot use this endpoint (it needs a staff Bearer token).

200: `{ "success": "RFID sign in" }` or `{ "success": "RFID sign out" }` (exact strings; nothing about the card owner is returned).

Rate limit: 60 taps a minute per staff user and 600 a minute per IP, then 429 (a separate counter from the legacy endpoint's).

| Status | `error.code` | When |
|---|---|---|
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |
| 404 | `not_found` | Unknown space |
| 422 | `parameter_missing` | `card_number` or `space_id` absent |
| 422 | `validation_failed` | `card_number` not a string, `space_id` not an integer |
| 422 | `card_not_linked` | The card is unknown (it is stored as an unlinked card so it appears in `GET /rfid_cards`) or known but has no owner yet. Nothing is signed in |
| 429 | `rate_limited` | Over the budget |
