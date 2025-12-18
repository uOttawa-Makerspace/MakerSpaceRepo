# Google Calendar MakerRoom Integration

> Automatically sync Google Calendar events with location STM 124 and STM 126 into MakerRoom, eliminating the need for manual entry.

---

## How It Works

- Any event where the service account is invited **and the location is `STM 124` or `STM 126`** will create or update a `SubSpaceBooking` in Makerroom.
- Register webhook weekly (cron job in GH Action) for Google to like us. Then immediately return 200 and do the sync in a job.
- `google_calendar_sync_job.rb` provides a sync token to keep track of when we accessed the list of events. Then we modify the db based on the event list.

## Testing

- Local testing can be done using **ngrok** to expose localhost to Google for webhooks (change the webhook url in `webhook_registrar.rb`)

## Note

The ICS to makerroom stuff is essentially disabled, as it doesn't quite work as intended and was breaking more things with the `before_save` that overrides updating subspace bookings (and possibly causing an infinite loop of broken?).
