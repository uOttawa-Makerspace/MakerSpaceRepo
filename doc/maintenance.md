# Maintenance

This document will outline best practices for performing server maintenance in several scenarios including full host migrations, site-breaking bugs and more.

## Introduction

In this guide we'll go over different scenarios, useful commands and procedures to follow in the event of the website should need to be inaccessible for a period of time. We can broadly break this down into 2 overarching categories, unplanned and planned.

## Tools

Whether the maintenance is planned or not, there are several tools at our disposal to facilitate an easy recovery. First if the website will be inaccessible it is preferable to have our own branding on the "Server Down" messaging than say Cloudflare. This signals we are aware the server is down and do not need to be informed. The app has no built-in maintenance mode, and the deploy workflow does not provide one. The way to show a branded "Server Down" page is Cloudflare Pages, which does not depend on the server being reachable.

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

Scheduled tasks run in the `worker` container (`bundle exec rake solid_queue:start`), from `config/recurring.yml`, in the application time zone (Eastern). Apart from the year-of-study bump (see below), nothing is scheduled with cron any more. The file has a block shared by production and staging, plus a block for each: the monthly CDEL report is production only, and the Google Calendar catch-up sync is staging only. If the `worker` container is not running, nothing is scheduled. Starting it again resumes the schedule; runs missed while it was down are not made up. Solid Queue records each tick once, so restarting the worker during a deploy does not run a task twice.

Check that tasks ran, in a Rails console (`docker compose -f docker-compose.production.yml exec web bin/rails console`):

```ruby
SolidQueue::RecurringTask.pluck(:key, :schedule)             # what is loaded
SolidQueue::RecurringExecution.order(run_at: :desc).limit(20).pluck(:task_key, :run_at)  # recent ticks
SolidQueue::FailedExecution.order(created_at: :desc).limit(5).pluck(:error)               # failures
```

The same data is in the `solid_queue_recurring_executions` and `solid_queue_failed_executions` tables, and the worker's logs (`docker compose -f docker-compose.production.yml logs worker`) show each job. Finished jobs are cleared out regularly, so check the recurring executions or the data a task writes (for example `PopularHour.maximum(:updated_at)`).

### Deploy step: remove the moved tasks from the host crontab

The host crontab still has `docker compose exec -T web` lines for these tasks (the containers have no cron of their own). They have not taken effect since 2026-08-31; `/var/www/makerrepo/log/cron_log.log` shows why. In the same deploy, remove the lines for the moved tasks (`crontab -e`) rather than fixing them: after this ships they run in the `worker` container, and a crontab line that starts working would run the task a second time (the CDEL report mailed twice, the popular hours counted twice).

Tasks that moved: popular hours, active volunteers, clear printers, the CDEL report, the Google Calendar webhook registration, and the locker expiry notices if a line for them exists. The print order reminder is removed (task and mailer method), so delete its line too. Keep only the `increment_year:increment_one_year` line; it is not scheduled in `recurring.yml`. The task claims the month (setting `increment_year_last_run`), so a second run in the same month changes nothing; `FORCE=1` repeats it. The manual repair `increment_year:fix` is guarded the same way (setting `increment_year_fix_run`, `FORCE=1` to repeat). Check in the cron log that it runs, since it goes through the same `docker compose exec` as the lines that stopped.

The locker notices migration must run before the first 8:30am run of the locker expiry notices (`locker_expiry_notices`). It marks the rentals that expired long ago as already notified, so renters are not mailed about old expiries. Running the migrations as part of the deploy covers this.

Post-deploy step for this release (Google Calendar webhook): run `bin/rails runner 'GoogleCalendar::WebhookRegistrar.register!'` once, right after the deploy. Channels registered before this release have no token, and the webhook refuses their pushes (401) until they are re-registered; there is no grace period for them. The same applies whenever `secret_key_base` is rotated: every channel's token is derived from it, so every channel is refused until it is re-registered with the same command.

### Failed and overdue job alerts

The `job_alerts` task (`JobAlertJob`, every 5 minutes, production and staging) mails the maintenance address (the one set on the printer issues page, `Setting.maintenance_email`) when a background job needs attention. It reports, once each:

- a failed execution (job class, queue, error class and ids; never the error message, which is in the queue dashboard);
- a scheduled execution still waiting 15 minutes after it was due (the dispatcher is not running);
- a claimed execution that has been running for more than an hour (the job is probably hung).

Only the last 24 hours are looked at, and at most 50 items go in one mail (the rest follow on the next run), so setting the address does not mail the whole history. Job arguments are never in the mail. With no address set nothing is mailed and nothing is marked as reported, so the alerts start when an address is set. The mail points at the queue dashboard (`/solid_queue`), where a failed job is retried or discarded.

Each item is marked as reported by a `settings` row, `job_alert:failed:<failed execution id>`, `job_alert:overdue:scheduled:<job id>` or `job_alert:overdue:claimed:<job id>`, with the value `sent`, so running twice, or two runs at once, mails nobody twice. A job that fails again after a retry is a new failed execution and is reported again. If the mail cannot be sent, the marks are removed and the task fails; the next run tries again. The rows are tiny and never pruned.

- To silence the alerts, clear the maintenance address (printer issues page), or remove the `job_alerts` entry from `config/recurring.yml`.
- To report an item again, delete its row: `Setting.where(key: "job_alert:failed:123").delete_all`. To report everything in the last 24 hours again: `Setting.where("key LIKE 'job_alert:%'").delete_all`.
- To mark the current failures as reported without mailing them, insert their rows first (`SolidQueue::FailedExecution.pluck(:id).each { |id| Setting.claim("job_alert:failed:#{id}", "sent") }`) and then set the address.

### Bulk mail tasks run by hand

`rake "update_profile:send_emails"` (profile update request, once per year, BCC groups of 498) and `rake confirmed_users:remind` (confirmation reminder, once per day, one user at a time) record their progress in the `settings` table, so running one again in the same period mails nobody and an interrupted run continues where it stopped. Each task prints how many groups or users it mailed. See [sign-up](flows/sign-up.md) and [profile and account deletion](flows/profile-and-account-deletion.md).

- The row is `bulk_mail:<task>:<period>` (`bulk_mail:update_profile:2026`, `bulk_mail:confirmed_users_remind:2026-11-06`). Its value is the id of the last user handled, or `done`. Rows are tiny and never pruned.
- `FORCE=1` starts the period over and mails everyone again, including people a live run already mailed. Do not run it while another run of the same task is still going.
- A run stopped with Ctrl-C or SIGTERM, or one that raised an error, hands its current claim back, so the next run repeats that user (`confirmed_users:remind`, one user at a time) or group of up to 498 (`update_profile:send_emails`). This is best effort: a run killed outright (SIGKILL, a crash, power loss) leaves its last user or group marked as sent. If handing the claim back fails too (database down, a second signal), the original error is still the one raised; the failure is reported through `Rails.error` with the key and claimed id, and the task prints the `Setting.set(...)` line that resets the row so that user or group is retried. To resume instead of using `FORCE=1`, look at the row (`Setting.find_by(key: "bulk_mail:update_profile:2026")` in a console) and set its value to the id of the last user who really got the mail, for example `Setting.set("bulk_mail:update_profile:2026", "12345")`; to start over, delete the row or set it to empty. A value that is neither a number nor `done` makes the task stop with an error.

### Backfilling the CDEL report

The report mailed on the 1st covers the month just ended. To mail a month again, or one that was missed, give the month as `YYYY-MM` (not later than the current month). Each run sends one mail:

```
docker compose -f docker-compose.production.yml exec web bin/rails "reports:send_cdel_report_to_sharepoint[2026-08]"
docker compose -f docker-compose.production.yml exec web bin/rails "reports:send_cdel_report_to_sharepoint[2026-09]"
docker compose -f docker-compose.production.yml exec web bin/rails "reports:send_cdel_report_to_sharepoint[2026-10]"
```

From a console, `CdelReportJob.perform_later(month: "2026-08")` does the same.

### Backfilling the popular hours

While the hourly task did not run, the popular hours stopped changing. To catch up, run once, with the start and end in the application time zone (the end is optional and never later than the last full hour before now):

```
docker compose -f docker-compose.production.yml exec web bin/rails "popular_hours:backfill[2026-08-30T21:00]"
```

For each hour in the range it takes the sample the hourly task would have taken at minute 50, counting only the sessions present at that moment, and folds it into the running means the same way. Before changing anything it writes the current rows to `tmp/popular_hours_snapshot_<time>.json` and prints the path, then prints the hours sampled, the rows changed and the hours skipped. Hours the hourly task has already recorded are skipped. The range is recorded, and a range overlapping one already backfilled is refused.

The backfill and the hourly task take the same database lock, so an hourly run that starts while the backfill is running waits for it (a few minutes for two months) and then records its hour as usual; nothing is counted twice. Start it just after minute 50 to avoid the wait.

The snapshot lives in the `web` container's `tmp/`, which is replaced on the next deploy, so copy it out straight away:

```
docker compose -f docker-compose.production.yml cp web:/rails/tmp/popular_hours_snapshot_<time>.json .
```

To undo the backfill, put the rows back exactly (this also clears the recorded range). Copy the snapshot back in first if the container has been replaced (`docker compose … cp ./popular_hours_snapshot_<time>.json web:/rails/tmp/`):

```
docker compose -f docker-compose.production.yml exec web bin/rails "popular_hours:restore_backfill[tmp/popular_hours_snapshot_<time>.json]"
```

Restoring returns the rows to how they were at the snapshot, so it also drops any samples the hourly task folded in since.

## Repository zip cache

Repository downloads are cached as zips in `tmp/repository_zips`. The cache is limited by `REPOSITORY_ZIP_CACHE_MAX_BYTES` (default 5 GB), the filesystem keeps `REPOSITORY_ZIP_MIN_FREE_BYTES` free (default 5 GB), and a zip larger than `REPOSITORY_ZIP_MAX_CACHED_ZIP_BYTES` (default 1 GB) is streamed instead of kept. An hourly job trims the cache (least recently used first) and removes partial zips older than an hour. Everything in `tmp/repository_zips` can be deleted at any time; zips are rebuilt on demand.

The cache lives in the `repository_zips` Docker volume (`staging_repository_zips` on staging), mounted at `/rails/tmp/repository_zips` in both the `web` and `worker` services, so it survives deploys and the hourly job manages the same files the web service writes. Emptying it is safe: `docker compose -f docker-compose.production.yml exec web sh -c 'rm -f /rails/tmp/repository_zips/*'` (or remove the volume). `df` inside the container measures the host filesystem behind the volume. If the free space cannot be read (unexpected `df` output) a request applies only the size cap, the problem is reported, and the hourly job evicts nothing that run.
