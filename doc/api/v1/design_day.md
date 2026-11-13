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
  "show_floorplans_day2": true,
  "floorplan_urls": ["https://.../floorplan.png"],
  "floorplan_titles": ["Level 1"],
  "floorplan_days": [1]
}
```

- Design day spans two days. `show_floorplans` is the day 1 switch, `show_floorplans_day2` the day 2 switch. `floorplan_days[i]` (`1` or `2`) is the day of `floorplan_urls[i]`; floorplans uploaded before days existed are day `1`. Both fields were added additively.

- Exactly these keys. Not sent (the app never read them): `id`, `is_live`, timestamps.
- `schedules` was removed: the student and judge schedules now live in the Google Sheet (`sheet_key`) and the Design Day app reads them from there. This is a deliberate exception to the additive-only rule; the Design Day app, the only client, stopped reading `schedules` before the field was dropped. The legacy endpoint still sends `design_day_schedules`.
- Differences from the legacy payload: no schedules, and `floorplan_urls` / `floorplan_titles` are always arrays (legacy: `null` when no floorplan). `floorplan_titles[i]` may be `null`.
- `semester` is `winter` (Jan-Apr), `summer` (May-Aug) or `fall` (Sep-Dec).
- With no design day configured the answer is a placeholder (today, empty `sheet_key`, `show_floorplans: false`, empty arrays); nothing is written (the legacy endpoint creates a row).
- Cached by nobody: `Cache-Control: no-store`.

## CORS

Only the Design Day origins may read this path from a browser: `https://designday.makerepo.com` and `https://<preview>.design-day-react.pages.dev` (anchored). Methods `GET`, `OPTIONS`; header `Content-Type`; no credentials. Every other origin (including the staff app, `localhost` and GitHub Pages) gets no `Access-Control-Allow-*` headers for this path. Non-browser clients are unaffected.
