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

Scheduled tasks run in the `worker` container (`bundle exec rake solid_queue:start`), from `config/recurring.yml`, in the application time zone (Eastern). Nothing is scheduled with cron any more. The file has a block shared by production and staging, plus a block for each: the monthly CDEL report is production only, and the Google Calendar catch-up sync is staging only. If the `worker` container is not running, nothing is scheduled. Starting it again resumes the schedule; runs missed while it was down are not made up. Solid Queue records each tick once, so restarting the worker during a deploy does not run a task twice.

Check that tasks ran, in a Rails console (`docker compose -f docker-compose.production.yml exec web bin/rails console`):

```ruby
SolidQueue::RecurringTask.pluck(:key, :schedule)             # what is loaded
SolidQueue::RecurringExecution.order(run_at: :desc).limit(20).pluck(:task_key, :run_at)  # recent ticks
SolidQueue::FailedExecution.order(created_at: :desc).limit(5).pluck(:error)               # failures
```

The same data is in the `solid_queue_recurring_executions` and `solid_queue_failed_executions` tables, and the worker's logs (`docker compose -f docker-compose.production.yml logs worker`) show each job. Finished jobs are cleared out regularly, so check the recurring executions or the data a task writes (for example `PopularHour.maximum(:updated_at)`).

### Deploy step: remove the moved tasks from the host crontab

The host crontab still has `docker compose exec` lines for these tasks. They have not taken effect since 2026-08-31, most likely because `-T` is missing (without it `docker compose exec` fails under cron, which has no terminal). Check first with `crontab -l` and the cron mail or log. Then, in the same deploy, remove the lines for the moved tasks (`crontab -e`) rather than fixing them: after this ships they run in the `worker` container, and a crontab line that starts working would run the task a second time (the CDEL report mailed twice, the popular hours counted twice).

Tasks that moved: popular hours, active volunteers, clear printers, the CDEL report, the Google Calendar webhook registration, and the locker expiry notices if a line for them exists. The print order reminder is removed (task and mailer method), so delete its line too. Keep only the `increment_year:increment_one_year` line; it is not scheduled in `recurring.yml`, and it needs `docker compose exec -T` to run from cron.

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
