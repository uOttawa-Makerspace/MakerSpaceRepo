# Spaces API

The space list and the staff member's current space. Replaces the `space_list` of `GET /staff_dashboard.json` and `PUT /staff_dashboard/change_space` for the React app. Conventions and error format: `README.md`. All endpoints need `Authorization: Bearer <access_token>` and a staff or admin account (S).

Space objects are always exactly `{ "id": 3, "name": "Makerspace" }`: no keycode, capacity or other column.

## GET /api/v1/spaces
200: every space, ordered by name.
```json
[ { "id": 3, "name": "Makerspace" }, { "id": 5, "name": "MTC" } ]
```

| Status | `error.code` | When |
|---|---|---|
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |

## GET /api/v1/me/space
The caller's current space (`users.space_id`). Same default as the legacy dashboard: with no space assigned, the first space.

200: `{ "id": 3, "name": "Makerspace" }`

| Status | `error.code` | When |
|---|---|---|
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |
| 404 | `not_found` | No space exists at all |

## PUT /api/v1/me/space
Request: `{ "space_id": 3 }` (an integer, or a numeric string). Sets the caller's current space, as `PUT /staff_dashboard/change_space` does (the user's `updated_at` is stamped; their stored profile is not re-validated, so a profile that fails a newer validation can still switch space).

200: `{ "id": 3, "name": "Makerspace" }`

| Status | `error.code` | When |
|---|---|---|
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |
| 404 | `not_found` | No such space (legacy: 500) |
| 422 | `parameter_missing` | `space_id` absent or null |
| 422 | `validation_failed` | `space_id` is not an integer or numeric string (`fields.space_id`) |
| 400 | `bad_request` | Malformed JSON |
