# /api/v1 conventions

JSON API for the React frontends (app.makerepo.com, designday.makerepo.com). Contracts live next to this file, one per resource (`session.md`, `users.md`, `spaces.md`, `presence.md`, `rfid.md`, `training_sessions.md`, `printers.md`, `shifts.md`, `design_day.md`, `support_requests.md`, `contact_infos.md`). The legacy HTML/JSON routes keep working until both frontends switch.

## Auth

- `Authorization: Bearer <access_token>` on every authenticated request. The scheme word is required. No cookies are read or set, and there is no CSRF token.
- Access tokens are 15-minute HS256 JWTs (claims `user_id`, `exp`, `ver`, `typ: "access"`). Get them from `POST /api/v1/session` and renew them with `POST /api/v1/session/refresh` (see `session.md`).
- The legacy 14-day token from `/login_authentication` is NOT accepted here.
- Deleted, deactivated and stale-version users are refused (401). A password change/reset, admin lock or account deletion ends all of a user's tokens.
- Roles: endpoints say P (public), U (any signed-in user), S (staff or admin), A (admin).

## Requests

- JSON bodies with `Content-Type: application/json`. Malformed JSON is a 400.
- Every response sets `Cache-Control: no-store`.
- CORS: only the known frontend origins, no credentials. Allowed request headers: `Authorization`, `Content-Type`, `X-Refresh-Token`, `Idempotency-Key`.
- Idempotency: an endpoint whose contract says so requires an `Idempotency-Key` header (1 to 255 characters; send a new random value, such as a UUID, for each submission and the same value when retrying it). Without one it answers 400 `idempotency_key_required`. A repeat with the same key by the same user gets the first response again and changes nothing; the same key with a different request (method, path or body) is a 422 `idempotency_key_reused`. Only a successful request records its key, so a refused request can be corrected and retried with the same key. Today only `POST /api/v1/training_sessions` uses it.

## Errors

Always JSON, always a real status:

```json
{
  "error": {
    "code": "validation_failed",
    "message": "Validation failed",
    "fields": { "email": ["is invalid"] },
    "reference": "3f2a9c1e"
  }
}
```

`code` is a stable machine string (branch on it, not on `message`); `fields` appears on 422 only; `reference` is on every error body and is the first 8 characters of the request id (the `X-Request-Id` response header): quote it when reporting a problem, it finds the request in the server logs and error tracker; some errors add extra keys (for example `support_email`).

| Status | Meaning                                                            | Typical codes                                                                    |
| ------ | ------------------------------------------------------------------ | -------------------------------------------------------------------------------- |
| 400    | Malformed request, or a required `Idempotency-Key` header missing  | `bad_request`, `idempotency_key_required`                                        |
| 401    | Missing/invalid/expired credentials                                | `unauthenticated`, `invalid_credentials`, `invalid_refresh_token`                |
| 403    | Authenticated but not allowed                                      | `forbidden`, `account_inactive`, `account_unconfirmed`                           |
| 404    | No such record or route (any unknown `/api/v1/...` path, any verb) | `not_found`                                                                      |
| 409    | Retry with the newest stored refresh token                         | `refresh_in_progress`                                                            |
| 422    | Validation, missing parameter, or an idempotency key reused        | `validation_failed`, `parameter_missing`, `last_admin`, `idempotency_key_reused` |
| 423    | Account locked                                                     | `account_locked`                                                                 |
| 429    | Rate limited                                                       | `rate_limited`                                                                   |
| 503    | Upstream unavailable, nothing saved                                | `service_unavailable`                                                            |

401 responses carry `WWW-Authenticate: Bearer realm="makerepo"`.

## Pagination

No endpoint returns an unbounded list. `GET /api/v1/users?query=` caps at 50 and reports `meta.truncated`; cursor pagination will be added additively when an endpoint needs it.

## Versioning

The version is in the path. Within `v1`, changes are additive only (new fields, new endpoints); clients must ignore unknown fields. Anything breaking becomes `/api/v2`, and `v1` is kept until the frontends have moved.

An unknown HTTP verb (for example `FOO /api/v1/session`) is rejected by Rails before any API code runs and gets Rails' default response, not the JSON error body.
