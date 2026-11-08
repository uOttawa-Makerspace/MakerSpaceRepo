# Design Day API

Public configuration for the Design Day app. Replaces `GET /admin/design_day/data` (which stays for now). Role: P (no token; any `Authorization` header is ignored).

## GET /api/v1/design_day

200:

```json
{
  "year": 2026,
  "semester": "winter",
  "day": "2026-03-14",
  "sheet_key": "1AbC...",
  "show_floorplans": true,
  "floorplan_urls": ["https://.../floorplan.png"],
  "floorplan_titles": ["Level 1"],
  "schedules": [
    {
      "start": "2000-01-01T09:00:00.000-05:00",
      "end": "2000-01-01T10:00:00.000-05:00",
      "title_en": "Judging",
      "title_fr": "Evaluation",
      "event_for": "judge"
    }
  ]
}
```

- Exactly these keys. Not sent (the app never read them): `id`, `is_live`, schedule `id`, `ordering`, `design_day_id`, timestamps.
- Differences from the legacy payload: schedules are under `schedules` (legacy: `design_day_schedules`), and `floorplan_urls` / `floorplan_titles` are always arrays (legacy: `null` when no floorplan). `floorplan_titles[i]` may be `null`.
- Schedule `start` and `end` are times of day (a `time` column). They are sent as ISO 8601 on the placeholder date 2000-01-01 with the app time zone's offset (Eastern), so read only the hour and minute; the date belongs to the design day's `day`.
- `semester` is `winter` (Jan-Apr), `summer` (May-Aug) or `fall` (Sep-Dec). `event_for` is `student` or `judge`. Schedules are ordered by `event_for`, `ordering`, `start`.
- With no design day configured the answer is a placeholder (today, empty `sheet_key`, `show_floorplans: false`, empty arrays); nothing is written (the legacy endpoint creates a row).
- Cached by nobody: `Cache-Control: no-store`.

## CORS

Only the Design Day origins may read this path from a browser: `https://designday.makerepo.com` and `https://<preview>.design-day-react.pages.dev` (anchored). Methods `GET`, `OPTIONS`; header `Content-Type`; no credentials. Every other origin (including the staff app, `localhost` and GitHub Pages) gets no `Access-Control-Allow-*` headers for this path. Non-browser clients are unaffected.
