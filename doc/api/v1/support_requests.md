# Support requests API

The Help form of the React app. Replaces the old `PUT /send_email`. Role: P or U (a valid Bearer token is optional).

## POST /api/v1/support_requests
Request:
```json
{ "name": "Ada", "email": "ada@example.com", "subject": "Printer will not start", "comments": "It beeps three times.", "app_version": "2.4.1" }
```
| Field | Rules |
|---|---|
| `name` | required, 2-200 chars |
| `email` | required, valid address, max 254 |
| `subject` | required, 10-200 chars |
| `comments` | required, max 5000 chars (plain text) |
| `app_version` | optional, max 50 chars; shown in the email |

Unknown fields are ignored. Values must be strings (an object or array counts as missing). Fields are trimmed.

When the caller is signed in, `name` and `email` are taken from the account and the posted values are ignored (they may be omitted). Anonymous callers' `email` is used as given.

Same path as the web Help form (`HelpController#create`): a `Help` record is saved (which opens the GitHub issue) and `MsrMailer.issue_email` is queued: To the reporter's email, Bcc `uottawa.makerepo@gmail.com`, subject `Issue Report | <subject>`.

202: `{ "status": "accepted" }`. The email is queued, not yet delivered; the body is never echoed back.

| Status | `error.code` | When |
|---|---|---|
| 400 | `bad_request` | Malformed JSON |
| 422 | `validation_failed` | Missing/invalid/too long fields (`fields.<name>`) |
| 429 | `rate_limited` | Over the limits below |
| 503 | `service_unavailable` | The GitHub issue could not be opened; nothing saved or sent. Retry later |

## Abuse control
No Turnstile on this endpoint (the React app cannot render it). The controls are rate limits, each counted separately: 5 per minute and 20 per hour per client IP, and, per signed-in user, 5 per minute and 20 per hour. A 429 carries the standard error body.
