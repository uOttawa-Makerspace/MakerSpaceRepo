# RFID API

Student-card taps, linking cards to users, and the phone NFC tap. Replaces `GET /rfid/get_unset_rfids`, `PUT /staff_dashboard/link_rfid`, `PUT /staff_dashboard/unlink_rfid` and (for the React app) `POST /rfid/card_number`. Conventions and error format: `README.md`. All endpoints need `Authorization: Bearer <access_token>` and a staff or admin account (S). Pi card readers keep using the legacy device endpoint (`POST /rfid/card_number` with a registered `mac_address`); it is not part of `/api/v1`.

## GET /api/v1/rfid_cards?linked=false
Unlinked cards that were tapped on a reader of the caller's assigned space (readers of every space when none is assigned), most recently tapped first, at most 5: the set `get_unset_rfids` returns. Only `linked=false` is supported.

200:
```json
[ { "card_number": "04A1B2C3", "tapped_at": "2026-10-29T14:03:11Z" } ]
```
`tapped_at` is ISO 8601 UTC (the legacy endpoint sent a ready-made "Tapped at <space> 5 minutes ago" sentence; format it client-side). A card whose last tap or scan was on a phone has no reader, so it never appears: a card first seen on a phone (via `rfid_taps` or `PUT /users/:id/rfid`) is stored without a reader, and a phone tap of a listed card clears its reader, so it drops off the list.

| Status | `error.code` | When |
|---|---|---|
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |
| 422 | `validation_failed` | `linked` missing or not `false` (`fields.linked`) |

## PUT /api/v1/users/:id/rfid
Request: `{ "card_number": "04A1B2C3" }`. Links a card to the user. `:id` is the numeric user id. A card that is in the list above is linked as is. A card no reader or tap ever saw (the staff app scans a brand-new card on the phone) is created and linked in one step: the row is stored with the card number exactly as sent (no case or separator normalisation; the readers store numbers as sent too) and no reader (`mac_address` null). `card_number` must be a string, non-blank, at most 64 characters, without control characters (the same rule as `rfid_taps`); nothing is created when it is invalid. Two simultaneous requests for the same new number create one card (serialised on the number; the second then gets the "another user" refusal if it was for a different user).

204, empty body (also for a card just created). Linking the card to the user who already holds it is a no-op 204. The card's other fields are untouched.

Refused with 422 and nothing changed (legacy did both silently):
- the card belongs to another user (`fields.card_number: ["is already linked to another user"]`): unlink it first;
- the user already holds a different card (`["user already has a card; unlink it first"]`).

| Status | `error.code` | When |
|---|---|---|
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |
| 404 | `not_found` | Unknown, soft-deleted or non-numeric user (an unknown card is no longer a 404: it is created; legacy: 500) |
| 422 | `parameter_missing` | `card_number` absent |
| 422 | `validation_failed` | `card_number` not a string or invalid (blank/too long/control characters), or one of the two refusals above |

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
| 422 | `card_not_linked` | The card is unknown (it is stored as an unlinked card with no reader, so it does not appear in `GET /rfid_cards`; link it with `PUT /users/:id/rfid`) or known but has no owner yet. Nothing is signed in |
| 429 | `rate_limited` | Over the budget |
