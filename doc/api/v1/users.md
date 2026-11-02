# Users API

Profile, staff search, role change and program membership. Replaces `GET /:username` (JSON branch), `GET /staff_dashboard/search`, `PATCH /admin/users/set_role` and `PATCH|POST /change_programs` for the React app. Conventions and error format: `README.md`. All endpoints need `Authorization: Bearer <access_token>`.

Usernames are letters (including accented ones), digits only, max 20 characters: no dot, space or slash. Percent-encode them in the path (`encodeURIComponent`); accented names such as `josé1` arrive as `jos%C3%A91`. Lookup is case-insensitive.

`avatar_url` is an absolute URL: the user's uploaded avatar (an Active Storage blob URL on the API host) or, without one, `<api origin>/default-avatar.png`. No legacy endpoint ever sent it.

## GET /api/v1/users/:username
Staff/admin: any user (soft-deleted accounts included, as in the legacy profile). Anyone else: only themself. A non-staff caller asking for any other username gets 403 whether or not that user exists.

200:
```json
{
  "user": {
    "id": 42, "username": "jdoe", "name": "Jane Doe", "email": "jdoe@uottawa.ca",
    "faculty": "Engineering", "program": "Mechanical Engineering", "year_of_study": "3rd year",
    "identity": "undergrad", "role": "regular_user",
    "avatar_url": "https://api.makerepo.com/rails/active_storage/blobs/redirect/<signed>/avatar.png",
    "rfid": { "card_number": "04A1B2C3" }
  },
  "programs": ["Volunteer Program", "Development Program"],
  "certifications": [
    { "id": 7, "updated_at": "2026-09-01T14:00:00Z", "training": { "id": 3, "name_en": "3D Printing" } }
  ],
  "remaining_trainings": [ { "id": 4, "name_en": "Laser Cutting" } ]
}
```
- `rfid` is `null` when no card is linked.
- `certifications`: active certifications, highest level per training, including trainings held only through a proficient project.
- `remaining_trainings`: every training the user has no active certification for. Before this endpoint the field was always empty (never sent); it now holds `User#remaining_trainings`.
- Never returned: `password`, `access_token`, `student_id`, `wallet`, `mac_address`, or any other column.

| Status | `error.code` | When |
|---|---|---|
| 401 | `unauthenticated` | No/invalid/expired token |
| 403 | `forbidden` | Non-staff caller, and the username is not theirs |
| 404 | `not_found` | Staff caller, unknown username |

## GET /api/v1/users?query=
Staff/admin. Substring match on name, email and username, case- and accent-insensitive (`zoe` finds `Zoë`). `%` and `_` match literally. At most 50 results, most recently active (`updated_at`) first; the oldest are dropped when truncating. `query` is 2 to 100 characters. Rate limit: 60 per minute per user (429 `rate_limited`).

200:
```json
{
  "users": [ { "id": 42, "username": "jdoe", "name": "Jane Doe", "email": "jdoe@uottawa.ca", "avatar_url": "https://..." } ],
  "meta": { "limit": 50, "truncated": false }
}
```
`truncated: true` means more than 50 users match: refine the query. (This is the first list endpoint; a cursor will be added later if needed, additively.)

| Status | `error.code` | When |
|---|---|---|
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |
| 422 | `parameter_missing` | `query` absent or empty |
| 422 | `validation_failed` | `query` shorter than 2 or longer than 100 characters after trimming (`fields.query`) |
| 429 | `rate_limited` | More than 60 searches in a minute |

## PATCH /api/v1/users/:id/role
Admin only. `:id` is the numeric user id.

Request: `{ "role": "admin" | "staff" | "regular_user" }` (`volunteer` is a program in the app, not assignable here; the legacy admin screen still accepts it).

204, empty body. The change runs through `User.change_roles!` (shared with `PATCH /admin/users/set_role`): one transaction, an audit line in the log, and, after commit, the demoted user's websocket connections are closed. Roles are read from the database on every request and are not in the token, so no token is revoked or needs re-issuing; the user's next request sees the new role.

An admin may change their own role (not an escalation) as long as another usable admin remains. A "usable" admin is one who is not locked.

| Status | `error.code` | When |
|---|---|---|
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not an admin (staff included) |
| 404 | `not_found` | Unknown, non-numeric or soft-deleted id |
| 422 | `parameter_missing` | `role` absent |
| 422 | `validation_failed` | `role` not one of the three (`fields.role`) |
| 422 | `last_admin` | The change would leave no usable admin (`fields.role`). Nothing is changed |

## PUT /api/v1/users/:id/programs
Staff/admin (including for themself). Replaces the development and volunteer memberships. The teams program is left untouched.

Request: `{ "development": true, "volunteer": false }`. Both keys are required and must be JSON booleans.

200: `{ "programs": ["Development Program"] }` (all of the user's programs after the change, teams included).

| Status | `error.code` | When |
|---|---|---|
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |
| 404 | `not_found` | Unknown or soft-deleted id |
| 422 | `parameter_missing` | A key is absent (`fields`) |
| 422 | `validation_failed` | A value is not `true`/`false` (`fields`). Nothing is changed |
