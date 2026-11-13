# Spaces API

The space list and the staff member's current space. Replaces the `space_list` of `GET /staff_dashboard.json` and `PUT /staff_dashboard/change_space` for the React app. Conventions and error format: `README.md`. All endpoints need `Authorization: Bearer <access_token>` and a staff or admin account (S).

Space objects are always exactly `{ "id": 3, "name": "Makerspace" }`: no keycode, capacity or other column.

## GET /api/v1/spaces

200: every space, ordered by name.

```json
[
  { "id": 3, "name": "Makerspace" },
  { "id": 5, "name": "MTC" }
]
```

| Status    | `error.code`                    | When                 |
| --------- | ------------------------------- | -------------------- |
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |

## GET /api/v1/me/space

The caller's current space: their saved space (`users.space_id`) when they may work in it, else the first space they may work in (the lowest id; for an admin, the first space). A staff member assigned to no space, and an admin when no space exists, get no space.

200: `{ "id": 3, "name": "Makerspace" }`, or `{ "space": null }` when the caller may work in no space. A client shows a "no assigned spaces" state for it: `GET /api/v1/spaces` still lists every space, but the caller may not use them.

| Status    | `error.code`                    | When                 |
| --------- | ------------------------------- | -------------------- |
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff |

## PUT /api/v1/me/space

Request: `{ "space_id": 3 }` (an integer, or a numeric string). Sets the caller's current space, as `PUT /staff_dashboard/change_space` does (the user's `updated_at` is stamped; their stored profile is not re-validated, so a profile that fails a newer validation can still switch space). Staff may switch only to a space they are assigned to; admins to any space (the same rule as the dashboard). A saved space they are no longer assigned to is refused too. `GET /api/v1/spaces` still lists every space.

200: `{ "id": 3, "name": "Makerspace" }`

| Status    | `error.code`                    | When                                                                                                                                      |
| --------- | ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff                                                                                                                      |
| 403       | `space_not_assigned`            | Staff (non-admin) named a space they are not assigned to; `message` is "You are not assigned to that space" and the current space is kept |
| 404       | `not_found`                     | No such space (legacy: 500)                                                                                                               |
| 422       | `parameter_missing`             | `space_id` absent or null                                                                                                                 |
| 422       | `validation_failed`             | `space_id` is not an integer or numeric string (`fields.space_id`)                                                                        |
| 400       | `bad_request`                   | Malformed JSON                                                                                                                            |
