# Training sessions API

The staff app's training-session screens. Replaces `GET /staff/training_sessions`, `GET /staff/training_sessions/new`, `POST /staff/training_sessions` and `POST /staff/training_sessions/:id/certify_trainees` for the React app. Conventions and error format: `README.md`. All endpoints need `Authorization: Bearer <access_token>` and a staff or admin account (S); guests get 401, regular users 403.

## GET /api/v1/training_sessions

The caller's OWN sessions (the instructor is the caller), also for admins. Newest update first. Not paginated (as legacy).

200:

```json
[
  {
    "id": 12,
    "course": "ENG 101",
    "level": "Beginner",
    "updated_at": "2026-10-29T14:03:11Z",
    "training": { "id": 4, "name_en": "3D Printing" },
    "space": { "id": 3, "name": "Makerspace" },
    "certifications": [{ "active": true, "user_id": 88 }],
    "users": [
      {
        "id": 88,
        "username": "jdoe",
        "name": "Jo Doe",
        "email": "jdoe@example.com"
      }
    ]
  }
]
```

`course` may be null. `certifications` lists active certifications only. `training` / `space` are null if the row was removed. No `keycode`, `role` or other columns.

## GET /api/v1/training_session_options?space_id=

Form data, computed as legacy `new` does. `space_id` is optional: omitted means the caller's space (assigned, else the first space), as legacy always did. Unknown or non-numeric `space_id`: 404. A `space_id` the caller may not work in (staff: not assigned to it; admins may use any space): 403 `space_not_assigned`, "You are not assigned to that space".

200:

```json
{
  "trainings": [[4, "3D Printing"]],
  "levels": ["Beginner", "Intermediate", "Advanced"],
  "course_names": ["ENG 101"],
  "instructors": [[7, "Sam Staff"]],
  "trainees": [[88, "Jo Doe"]]
}
```

`trainings`: trainings offered in the space. `instructors`: every staff and admin user. `trainees`: users signed in to the space now.

## POST /api/v1/training_sessions

Headers: `Idempotency-Key: <a new UUID per submission>` is required (see Idempotency below).

Request: `{ "space_id": 3, "training_id": 4, "level": "Beginner", "course": "ENG 101", "instructor_id": 7, "user_ids": [88, "89"] }`

- `space_id`, `training_id`, `level` are required. `course` is optional (string, at most 255; a value matching a course name links it; `"no course"` is stored as null, as legacy). `user_ids` is optional (integers or numeric strings, duplicates ignored); trainees need not be signed in.
- `instructor_id`: staff may omit it or send their own id. Admins may name any staff or admin user.

201: `{ "id": 12 }`

| Status    | `error.code`                    | When                                                                                                                                                                                                                                                        |
| --------- | ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff                                                                                                                                                                                                                                        |
| 403       | `forbidden`                     | Staff (non-admin) sent an `instructor_id` that is not their own; nothing is created                                                                                                                                                                         |
| 403       | `space_not_assigned`            | Staff (non-admin) named an existing space they are not assigned to; `message` is "You are not assigned to that space"; nothing is created                                                                                                                   |
| 422       | `validation_failed`             | `fields` keyed by `space_id` (missing/unknown), `training_id` (missing/unknown/not offered in the space), `level` (not one of the three levels), `course`, `instructor_id` (admin only: not a staff member), `user_ids` (not a list of ids, or unknown ids) |
| 400       | `idempotency_key_required`      | No `Idempotency-Key` header, or a blank one or one longer than 255 characters; nothing is created. The message asks the user to reload the app (an app that does not send the header is out of date). Checked after sign-in and role, before the body       |
| 422       | `idempotency_key_reused`        | The key was already used by this user for a different request (another body); nothing is created                                                                                                                                                            |
| 400       | `bad_request`                   | Malformed JSON                                                                                                                                                                                                                                              |

### Idempotency

The app makes one key per submission and sends the same key again when it retries that submission (for example after a timeout or a network error).

- The first request with a key that creates the session records the key for the caller together with its response (`201` and `{ "id": ... }`), in the same transaction as the session.
- A repeat with the same key by the same user and the same body answers that recorded response again (`201`, the same `id`) and creates nothing. The body is compared with its object keys in any order; values and list order must match.
- Two requests with the same key at the same time create one session: the second waits for the first, then answers with the first one's response.
- Keys belong to the caller: another user may send the same value and gets their own session.
- A refused request (401, 403, 422, 400) records nothing, so the user can correct the form and retry; the app sends a new key when the form changes.
- Recorded keys are kept (they are not expired or pruned); a key only ever answers a repeat of its own submission.

## POST /api/v1/training_sessions/:id/certifications

No body. Certifies every enrolled trainee at the session's level, exactly as legacy `certify_trainees`: a user who already holds an active certification for the same training at the same level (from any session or a proficient project) is skipped, so repeating the call is harmless. No email is sent (legacy sends none).

200: `{ "certified": true }`. `false` when any certification failed to save (the others are kept; legacy behaviour).

The session's instructor is never certified by their own session (admins included): if the instructor is among the trainees they are skipped, the other trainees are certified as usual, and the response gains `"self_skipped": true` (e.g. `{ "certified": true, "self_skipped": true }`). The key is absent otherwise. Skipping the instructor is not a failure and does not make `certified` false.

| Status    | `error.code`                    | When                                                                                                |
| --------- | ------------------------------- | --------------------------------------------------------------------------------------------------- |
| 401 / 403 | `unauthenticated` / `forbidden` | No token / not staff; or staff who is not the session's instructor (admins may certify any session) |
| 404       | `not_found`                     | No such session, or `:id` is not an integer                                                         |
