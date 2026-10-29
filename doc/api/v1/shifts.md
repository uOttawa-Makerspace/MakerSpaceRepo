# Shifts API

The staff app's Shifts calendar. Replaces `GET /staff/my_calendar/json/:space_id?event_type=shift`. Conventions and error format: `README.md`. Needs `Authorization: Bearer <access_token>` and a staff or admin account (S).

The data is the published (non-draft) `events` of `event_type = "shift"` that admins create in the admin calendar. (The retired `Shift` model and `shifts` table are not used.)

## GET /api/v1/spaces/:id/shifts?start=&end=&user_id=
- `start`, `end` (required): ISO 8601 date-times, for example `2026-11-01T00:00:00-04:00`. `end` must not be before `start`, and the range is at most 100 days.
- `user_id` (optional): integer; only shifts that user is assigned to (their co-assignees still appear in the title). An unknown user gives an empty list.
- Any staff member may read any space and filter by any user (as the legacy does).

200: events ordered by start time, shaped for FullCalendar.
```json
[ { "id": "event-12", "title": "Shift for Ann Staff, Bob Staff",
    "start": "2026-11-02T09:00:00-05:00", "end": "2026-11-02T11:00:00-05:00", "allDay": false,
    "extendedProps": { "eventType": "shift", "description": "Front desk",
                       "background": "linear-gradient(to right, #ff0000 0.0%, #ff0000 50.0%, #3788d8 50.0%, #3788d8 100.0%);" } } ]
```
- A one-off event is listed only when it lies fully inside `[start, end]`. A recurring event (`recurrence_rule`) is expanded to the occurrences that start in the window, with ids `event-<id>-<unix start>`.
- `background` is `#3788d8` for an unassigned shift, otherwise a gradient of the assignees' space colours (`staff_spaces.color`, default `#3788d8`).
- Only the fields the app reads are sent: no `name`, `draft`, `hasCurrentUser`, and no email or other user column (assignee display names appear in `title`).

| Status | `error.code` | When |
|---|---|---|
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |
| 404 | `not_found` | No such space (or a non-integer id) |
| 422 | `validation_failed` | `start`/`end` missing or not ISO 8601, `end` before `start`, range over 100 days, or `user_id` not an integer (`fields` names each) |
