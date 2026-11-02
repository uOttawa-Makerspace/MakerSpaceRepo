# Presence API

Who is in a space, and signing people in and out. Replaces `GET /staff_dashboard.json` (`space`, `space_users`), `PUT /staff_dashboard/add_users` and `PUT /staff_dashboard/remove_users` for the React app. Conventions and error format: `README.md`. All endpoints need `Authorization: Bearer <access_token>` and a staff or admin account (S). `:id` is the numeric space id (a non-numeric id is the generic JSON 404).

A user is "in" a space while they have a lab session there whose `sign_out_time` is in the future (the rule `Space#signed_in_users` uses). Soft-deleted accounts never appear.

## GET /api/v1/spaces/:id/presence
200:
```json
{
  "space": { "id": 3, "name": "Makerspace" },
  "users": [
    {
      "id": 42, "username": "jdoe", "name": "Jane Doe", "email": "jdoe@uottawa.ca", "flagged": false,
      "avatar_url": "https://api.makerepo.com/default-avatar.png",
      "certifications": [ { "id": 7, "name": "Basic Training" } ],
      "signed_safety_sheet": true,
      "membership_status": false
    }
  ],
  "current_user": { "id": 9 }
}
```
- `users` are ordered by id, each user once however many sessions they have.
- `certifications`: the user's active certifications (all spaces); `name` is the training's English name, `"Unknown"` when the certification has no training session.
- `signed_safety_sheet`: the user has a walk-in safety sheet (any space). `membership_status`: the user has a paid, unexpired membership.
- `avatar_url`: the uploaded avatar (Active Storage URL) or `<api origin>/default-avatar.png`.
- `current_user.id` is the caller (the legacy payload never sent it).
- Never returned: any other user column (`access_token`, `student_id`, `password`, `wallet`, ...), or any space column besides `id` and `name` (`keycode`).
- A fixed number of queries however many users are present.

| Status | `error.code` | When |
|---|---|---|
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |
| 404 | `not_found` | Unknown space |

## POST /api/v1/spaces/:id/presence
Request: `{ "username": "jdoe" }` (case-insensitive). Signs the user in: one lab session row for the space, `sign_in_time` now, `sign_out_time` six hours from now, as `sign_in_users` does.

204, empty body. **Idempotent**: a user who already has an unexpired session in this space gets no new row and the existing session is left as it is (legacy added a duplicate row on every call). A session in another space or an expired one does not count.

| Status | `error.code` | When |
|---|---|---|
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |
| 404 | `not_found` | Unknown or soft-deleted user, or unknown space (legacy ignored an unknown username and answered ok) |
| 422 | `parameter_missing` | `username` absent |

## DELETE /api/v1/spaces/:id/presence/:username
Signs the user out: every unexpired lab session the user has in THIS space gets `sign_out_time` = now. Percent-encode the username (`encodeURIComponent`).

204, empty body. **Idempotent**: a user who is not in the space is a 204 and nothing changes (legacy: 500). Sessions in other spaces are untouched (legacy ended the user's latest session in any space).

| Status | `error.code` | When |
|---|---|---|
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |
| 404 | `not_found` | Unknown or soft-deleted user, or unknown space |
