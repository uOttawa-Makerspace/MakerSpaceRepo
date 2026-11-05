# Maintenance

This document will outline best practices for performing server maintenance in several scenarios including full host migrations, site-breaking bugs and more.

## Introduction

In this guide we'll go over different scenarios, useful commands and procedures to follow in the event of the website should need to be inaccessible for a period of time. We can broadly break this down into 2 overarching categories, unplanned and planned.

## Tools

Whether the maintenance is planned or not, there are several tools at our disposal to facilitate an easy recovery. First if the website will be inaccessible it is preferable to have our own branding on the "Server Down" messaging than say Cloudflare. This signals we are aware the server is down and do not need to be informed. We have two different tools to accomplish this.

- Cloudflare Pages
- Capistrano

Capistrano can be used with the follow command
`cap production maintenance:enable REASON="Immediate Unexpected Maintenance" UNTIL="HH:HH (H:MM AM/PM)"`
Capistrano is launched from your local development environment and effectively supplants MakerRepo until the disable command
`cap production maintenance:disable` is run. The downside to this method is it requires the server to be reachable, so in cases where the server will not at all times be reachable we can use Cloudflare

Direct the cname record for MakerRepo to makerepo-is-down.pages.dev for a server-less static down page.

## Unplanned

Unplanned maintenance only occurs in a situation it is absolutely necessary for the website to be inaccessible and ideally for the shortest period of time. Some times unplanned maintenance should be considered:

- Core functionality of the site is broken
- Public facing functionality that a normal user could be expect to use is broken
- A major vulnerability is discovered

In the case of unplanned maintenance:

- [ ] Identity the issue and it's scope
- [ ] Communicate the issue to management and your proposed solution
- [ ] If the issue is severe and requires immediate correct you can use your judgement to begin correction without approval
- [ ] Based on whether the server will be offline, put up the appropriate maintenance page.
  - In general, code issues do not require a restart of the server because of our CD pipeline.
- [ ] Use the script in the home folder of the deploy user to create a backup of the database.
- [ ] Implement your solution
- [ ] Verify it's implementation via direct access to MakerRepo through the Server IP's instead of URL.
- [ ] Communicate the fix and any effects it might have, for example if you had to rollback the database.

## Planned

Planned Maintenance should be conducted when feasible outside of business hours with a healthy margin to fix before operations resume (ie a Saturday.) Planned server maintenance generally only happens during upgrades or migrations due to non-urgent matters so we have the luxury of picking our time.

Here are some things to keep in mind:

- Confirm with stakeholders time of planned maintenance beforehand
- Create an announcement visible to all users, even non-signed in, at least 24 hours in advance warning of the maintenance.
- Based on whether the server will be available for the duration of the period, select the appropriate maintenance page.
- Ensure you have the appropriate backups (DB, system images)
- In the case of a migration, have both servers running simultaneously only after DNS points to the new server and functionality has been verified should you shutdown the old server.

## Scheduled tasks

Solid Queue now runs the recurring tasks. They are listed in `config/recurring.yml`, and they need a running Solid Queue worker. Production still has a hand-maintained crontab, so each task that moved would run twice (once from the crontab, once from Solid Queue) unless its crontab line is removed in the same deploy.

In the deploy that ships the recurring tasks, remove these lines from the crontab:

- `popular_hours` (the popular hours calculation)
- `active_volunteers` (both entries)
- `printers:clear_printers`
- `lockers:notify_expired_rentals`, if it is there
- the Google Calendar webhook registration
- `reports:send_cdel_report_to_sharepoint`
- the retired `print_order_notifications` reminder

On staging, also remove the `GoogleCalendarSyncJob` line.

One line stays: `increment_year`. It is not a Solid Queue task and keeps running from the crontab.

The locker notices migration must run before the first 8:30am run of the locker expiry notices (`locker_expiry_notices`). It marks the rentals that expired long ago as already notified, so renters are not mailed about old expiries. Running the migrations as part of the deploy covers this.

Post-deploy step for this release (Google Calendar webhook): run `bin/rails runner 'GoogleCalendar::WebhookRegistrar.register!'` once, right after the deploy. Channels registered before this release have no token, and the webhook refuses their pushes (401) until they are re-registered; there is no grace period for them. The same applies whenever `secret_key_base` is rotated: every channel's token is derived from it, so every channel is refused until it is re-registered with the same command.


## Repository zip cache

Repository downloads are cached as zips in `tmp/repository_zips`. The cache is limited by `REPOSITORY_ZIP_CACHE_MAX_BYTES` (default 5 GB), the filesystem keeps `REPOSITORY_ZIP_MIN_FREE_BYTES` free (default 5 GB), and a zip larger than `REPOSITORY_ZIP_MAX_CACHED_ZIP_BYTES` (default 1 GB) is streamed instead of kept. An hourly job trims the cache (least recently used first) and removes partial zips older than an hour. Everything in `tmp/repository_zips` can be deleted at any time; zips are rebuilt on demand. See `doc/flows/repositories-and-makes.md`.

The cache lives in the `repository_zips` Docker volume (`staging_repository_zips` on staging), mounted at `/rails/tmp/repository_zips` in both the `web` and `worker` services, so it survives deploys and the hourly job manages the same files the web service writes. Emptying it is safe: `docker compose -f docker-compose.production.yml exec web sh -c 'rm -f /rails/tmp/repository_zips/*'` (or remove the volume). `df` inside the container measures the host filesystem behind the volume. If the free space cannot be read (unexpected `df` output) a request applies only the size cap, the problem is reported, and the hourly job evicts nothing that run.
