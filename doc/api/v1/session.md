# Session API

Login, token refresh, "who am I" and logout. Replaces `POST /login_authentication`, `GET /check_signed_in` and `GET /logout` for the React app. Conventions: `README.md`.

## Tokens

| Token | Format | Lifetime | Where it lives |
|---|---|---|---|
| Access | HS256 JWT (`user_id`, `ver`, `typ: "access"`, `iat`, `exp`) | 15 minutes | memory; sent as `Authorization: Bearer` |
| Refresh | 32 random bytes, base64url (43 chars). Stored only as a SHA-256 digest | 30 days, sliding on each rotation, never beyond 90 days from the first login | the client's persistent storage |

A refresh token is single-use: refreshing returns a NEW refresh token and revokes the old one. All tokens descending from one login form a "family" (one per device/browser). Replaying an already-used refresh token is handled in two ways:
- **within 30 seconds of its rotation** (typically a second browser tab refreshing at the same moment): `409 refresh_in_progress`. Nothing is revoked and no token is returned. The client must wait briefly, re-read the refresh token the other tab stored, and retry with it.
- **after 30 seconds**: treated as theft. The whole family is revoked and the answer is `401 invalid_refresh_token`; the user has to log in again on that device.

A password change/reset, an admin lock or deletion of the account ends every access token and every refresh token of the user.

## POST /api/v1/session (login)
Public. Rate limited: 10 per 3 minutes per IP, the SAME budget as the HTML login and SAML sign-in.

Request:
```json
{ "login": "jdoe", "password": "..." }
```
`login` is a username or an email (case-insensitive).

201:
```json
{
  "access_token": "eyJ...",
  "access_token_expires_at": "2026-10-28T15:15:00Z",
  "refresh_token": "Hq3...43 chars",
  "user": { "id": 42, "username": "jdoe", "name": "Jane Doe", "role": "staff" }
}
```
`user` is an allowlist: `id`, `username`, `name`, `role` (`regular_user`, `volunteer`, `staff`, `admin`). Nothing else is returned.

| Status | `error.code` | When |
|---|---|---|
| 401 | `invalid_credentials` | Wrong password or unknown login (same answer for both). Failed attempts count towards the 5-attempt lockout |
| 403 | `account_unconfirmed` | Correct password, email not confirmed |
| 403 | `account_inactive` | Correct password, account deactivated (`support_email` included) |
| 423 | `account_locked` | Locked: 5 failed attempts (message says how long to wait, 5 minutes), or locked by an admin (no wait). Checked before the password, so a locked account is refused even with the right password. `support_email` included |
| 422 | `parameter_missing` | `login` or `password` absent (`fields` names it) |
| 429 | `rate_limited` | Too many sign-in attempts |

## POST /api/v1/session/refresh
Public (the refresh token is the credential). 120 per minute per IP.

Request: `{ "refresh_token": "Hq3..." }`

200: same body as login (new `access_token`, new `refresh_token`, `user`). Store the new refresh token and drop the old one at once.

| Status | `error.code` | When |
|---|---|---|
| 401 | `invalid_refresh_token` | Unknown, expired, revoked, used more than 30 seconds ago (family is revoked), or its user can no longer sign in |
| 409 | `refresh_in_progress` | Used less than 30 seconds ago and the family is still live. Not a failure: retry with the newest stored token |
| 422 | `parameter_missing` | `refresh_token` absent |

## GET /api/v1/session
`Authorization: Bearer <access>`. 200 `{ "user": { "id", "username", "name", "role" } }`. 401 `unauthenticated` if the token is missing, malformed, expired or revoked by a version bump. It does not issue tokens (use refresh).

## DELETE /api/v1/session (logout)
Body `{ "refresh_token": "..." }` or header `X-Refresh-Token: ...`. Revokes that token's whole family (this device) and answers 204. Idempotent: an unknown, expired or already revoked token, or none at all, is still 204. Other devices stay signed in. The access token is not blacklisted; it expires within 15 minutes, so also discard it client-side.

## Flow for the React app
1. Login -> keep the access token in memory, the refresh token in storage; remember `access_token_expires_at`.
2. Send `Authorization: Bearer <access>` on every API call.
3. On a 401 `unauthenticated` (or shortly before `access_token_expires_at`): call refresh ONCE, store the new pair, retry the failed request once.
4. **Single-flight the refresh.** Within one tab, requests that get a 401 at the same time must wait on one shared refresh call. Across tabs, use a lock (for example the Web Locks API or a `storage` event) and re-read the stored refresh token before refreshing. If you still get `409 refresh_in_progress`, wait 200 to 500 ms, re-read the stored token (the other tab saved a new one) and retry, at most a few times; if none is stored, treat it as logged out. The 30-second window is a safety net, not a substitute for single-flight.
5. If refresh answers 401 `invalid_refresh_token`: clear storage and send the user to the login screen. Do not retry.
6. On app start, if a refresh token is stored, call refresh (or `GET /session` if the access token is still valid) to restore the session instead of the legacy `check_signed_in`.
7. Logout: `DELETE /api/v1/session` with the refresh token, then clear storage whatever the answer.

Never log or persist tokens in anything but the one storage location, and never store the whole user object beyond `id`, `username`, `name`, `role`.
