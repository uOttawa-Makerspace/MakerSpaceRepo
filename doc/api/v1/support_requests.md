# Support requests API

The Help form of the React app. Replaces the old `PUT /send_email`. Role: P or U (a valid Bearer token is optional).

## POST /api/v1/support_requests

Request:

```json
{
  "name": "Ada",
  "email": "ada@example.com",
  "subject": "Printer will not start",
  "comments": "It beeps three times.",
  "app_version": "2.4.1"
}
```

| Field         | Rules                                      |
| ------------- | ------------------------------------------ |
| `name`        | required, 2-200 chars                      |
| `email`       | required, valid address, max 254           |
| `subject`     | required, 10-200 chars                     |
| `comments`    | required, max 5000 chars (plain text)      |
| `app_version` | optional, max 50 chars; shown in the email |

Unknown fields are ignored. Values must be strings (an object or array counts as missing). Fields are trimmed.

When the caller is signed in, `name` and `email` are taken from the account and the posted values are ignored (they may be omitted); the account's own name and email are not checked against the rules above. Anonymous callers' `email` is used as given, but only as Reply-To and in the email body (never as a recipient).

Same path as the web Help form (`HelpController#create`): the request only saves a `Help` record and queues `HelpFilingJob`. It answers once the record is saved; the GitHub issue and the email come after, from the job.

The job sends the email and opens the GitHub issue, each once. Signed in: `MsrMailer.issue_email_copy_to_team` To `uottawa.makerepo@gmail.com`, in English, and `MsrMailer.issue_email` To the account email, in the account's language. Anonymous (`MsrMailer.issue_email_to_team`): To `uottawa.makerepo@gmail.com` only, Reply-To the posted email. Subject `Issue Report | <subject>` (in English). The public GitHub issue text has `@`, `#<n>`/`GH-<n>` neutralised with a zero-width joiner and `< > &` escaped. When GitHub is unavailable the job tries again later (3 runs with a growing wait, then every 15 minutes for about an hour and a half); the caller is not told.

202: `{ "status": "accepted" }`. The request is saved; the email and the GitHub issue are not sent yet. The body is never echoed back. A 202 is also the answer when the job could not be queued: the saved request is queued again within about 15 minutes. A retry after a 202 sends a second request.

| Status | `error.code`        | When                                                         |
| ------ | ------------------- | ------------------------------------------------------------ |
| 400    | `bad_request`       | Malformed JSON                                               |
| 422    | `validation_failed` | Missing/invalid/too long fields (`fields.<name>`)            |
| 429    | `rate_limited`      | Over the limits below                                        |
| 500    | `internal_error`    | The request could not be saved; nothing is sent. Retry later |

## Rate limits

No Turnstile on this endpoint (the React app cannot render it). The controls are rate limits, each counted separately: 5 per minute and 20 per hour per client IP, and, per signed-in user, 5 per minute and 20 per hour. A 429 carries the standard error body.
