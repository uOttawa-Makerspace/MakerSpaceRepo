# Printers API

The staff app's printer list, printer-to-user assignment and printer issues. Replaces `GET /printers/printer_data`, `PATCH /printers/link_printer_to_user`, `GET /printer_issues` and the dead `POST /printer_issues/:id/resolve` for the React app. Conventions and error format: `README.md`. All endpoints need `Authorization: Bearer <access_token>` and a staff or admin account (S). `Content-Type: application/json` for bodies.

## GET /api/v1/printer_types?include=printers

200: every printer type, ordered by name (case-insensitive), with its printers in the legacy order (type, then number length, then number).

```json
[
  {
    "id": 1,
    "name": "Ultimaker 3",
    "short_form": "UM3",
    "available": true,
    "printers": [
      { "id": 7, "number": "01", "maintenance": false, "has_issues": true }
    ]
  }
]
```

- Without `include`, the `printers` key is absent. `include` accepts only `printers`.
- `has_issues` is true when the printer has ANY issue row, resolved or not (same as the legacy `printer_data`).
- No per-type or per-printer queries.

| Status    | `error.code`                    | When                                                    |
| --------- | ------------------------------- | ------------------------------------------------------- |
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff                                    |
| 422       | `validation_failed`             | `include` is anything but `printers` (`fields.include`) |

## POST /api/v1/printers/:id/assignments

Request: `{ "user_id": 42 }` (an integer or numeric string), or `{ "user_id": "clear" }`.

Same effect as the legacy `link_printer_to_user`, in one transaction (the printer row is locked):

- Assign: a new `printer_sessions` row (`printer_id`, `user_id`, `in_use: true`); the printer's previous session, if it was `in_use`, is set to `in_use: false`.
- `"clear"`: the printer's latest session is set to `in_use: false`; no row is created. A printer with no session is a no-op.

204, no body. No email is sent.

| Status    | `error.code`                    | When                                                              |
| --------- | ------------------------------- | ----------------------------------------------------------------- |
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff                                              |
| 404       | `not_found`                     | No such printer, or no such (or deleted) user. Nothing is written |
| 422       | `parameter_missing`             | `user_id` absent or null                                          |
| 422       | `validation_failed`             | `user_id` is neither a user id nor `"clear"` (`fields.user_id`)   |

## GET /api/v1/printer_issues

200: every issue (active and resolved), ordered by printer then id.

```json
[
  {
    "id": 5,
    "printer_id": 7,
    "reporter": "Rita Reporter",
    "summary": "Nozzle clogged",
    "description": "text",
    "created_at": "2026-10-20T15:04:05.123Z",
    "active": true
  }
]
```

`reporter` is the reporter's display name only (null if the account is gone); no email or other user field is ever sent. `created_at` has the legacy format (UTC, milliseconds).

| Status    | `error.code`                    | When                 |
| --------- | ------------------------------- | -------------------- |
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |

## PATCH /api/v1/printer_issues/:id

Resolve an issue. Request: `{ "active": false }` (boolean false or the string `"false"`). Sets `active: false` and nothing else (other fields in the body are ignored). No email is sent and the printer's `maintenance` flag is not changed. Resolving an already resolved issue is a 204.

204, no body.

| Status    | `error.code`                    | When                                                                                               |
| --------- | ------------------------------- | -------------------------------------------------------------------------------------------------- |
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff                                                                               |
| 404       | `not_found`                     | No such issue (or a non-integer id)                                                                |
| 422       | `validation_failed`             | `active` absent (`is required`) or anything but false (`must be false`); re-opening is not offered |
