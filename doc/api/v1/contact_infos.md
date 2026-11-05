# Contact infos API

Public contacts and their opening hours. Replaces `GET /hours` (JSON), which could not work. Role: P.

**Frontend change needed** (frontend-followups item 8): the Space Hours screen read `opening_hour.students/public/summer`, which never existed. Update its types to the shape below.

## GET /api/v1/contact_infos

200: contacts with `show_hours = true`, ordered by name. Hidden contacts, `url`, `space_id` and ids are never sent.

```json
[
  {
    "name": "Makerspace",
    "email": "makerspace@uottawa.ca",
    "address": "STEM 100",
    "phone_number": "613-555-0100",
    "opening_hours": [
      {
        "target_en": "Students",
        "target_fr": "Etudiants",
        "notes_en": "Bring your card",
        "notes_fr": null,
        "closed_all_week": false,
        "days": {
          "sunday": { "status": "closed", "opening": null, "closing": null },
          "monday": {
            "status": "open",
            "opening": "09:00",
            "closing": "17:30"
          },
          "tuesday": {
            "status": "open",
            "opening": "09:00",
            "closing": "17:30"
          },
          "wednesday": {
            "status": "open",
            "opening": "09:00",
            "closing": "17:30"
          },
          "thursday": {
            "status": "open",
            "opening": "09:00",
            "closing": "17:30"
          },
          "friday": {
            "status": "open",
            "opening": "09:00",
            "closing": "17:30"
          },
          "saturday": { "status": "hidden", "opening": null, "closing": null }
        }
      }
    ]
  }
]
```

- `opening_hours[]` is one period per audience/season (`target_*` names it, e.g. "Students", "Summer"), in creation order. It may be empty.
- `days` always has the seven keys, Sunday first. `status` is `open`, `closed` or `hidden` (the admin "closed all day?" select); `hidden` means do not display that day. `opening` / `closing` are 24-hour `"HH:MM"` wall-clock strings, or `null`.
- `closed_all_week: true` means the whole period is closed. Periods the admin marked "hidden" for the week are omitted.
- All text is raw (both languages); the client picks `_en` or `_fr`.
