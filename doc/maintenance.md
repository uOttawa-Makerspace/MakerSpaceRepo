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

## Rails environment of the Docker image

The image is built with `RAILS_ENV=staging` as its default (`Dockerfile`), and Puma also falls back to staging (`config/puma.rb`). Production runs as production only because `docker-compose.production.yml` sets `RAILS_ENV: production` on the `web` and `worker` services; `docker-compose.staging.yml` sets `RAILS_ENV: staging`. The assets are precompiled under the default, which is fine: the Vite build does not depend on the environment.

Run one-off production commands through the compose file, so they get its environment (`docker compose -f docker-compose.production.yml exec web bin/rails ...` in the running container, or `docker compose -f docker-compose.production.yml run --rm web bin/rails ...` for a new one). A container started any other way, for example with a bare `docker run` of the image, runs as staging (staging mail hosts and settings, debug logging) unless it is given the environment explicitly: `docker run -e RAILS_ENV=production ...`, along with the database and secret settings the compose file provides.

## Releasing to production

A push to `master` builds the image, and the deploy workflow then runs `docker compose -f docker-compose.production.yml pull` and `up -d --remove-orphans` on the server. That recreates `web` and `worker` at the same time; the worker does not need to be stopped first. The new `web` runs `bin/rails db:prepare` before Puma starts (`bin/docker-entrypoint`, under `set -e`). If a migration raises, the new `web` exits and restarts in a loop, and since the old `web` has already been stopped the site stays down until the data is fixed and the deploy runs again, or the old image is put back. Every migration below that "stops with a message" therefore stops the whole site on production, so check its data first.

### Before merging to master

- [ ] Take a fresh database backup right before the deploy (the script in the deploy user's home folder), and keep it until the release has run for a few days. Some changes cannot be undone by redeploying the old image (see "Rollback limits" below), so this backup is the way back.
- [ ] Close any Rails console left open on the server. An open transaction makes the concurrent index builds wait.
- [ ] Run these read-only queries in a database console on production. Each must return 0 rows (or a count of 0), except where a comment says otherwise. A non-zero answer means the matching migration will stop on boot: settle those rows first, as its section below says.

```sql
SELECT count(*) FROM locker_rentals WHERE preferred_locker <> '';
SELECT user_id, announcement_id FROM announcement_dismisses GROUP BY 1,2 HAVING count(*)>1;
SELECT user_id, program_type FROM programs GROUP BY 1,2 HAVING count(*)>1;
SELECT user_id, volunteer_task_id, date_of_task, total_time FROM volunteer_hours WHERE approval IS NULL GROUP BY 1,2,3,4 HAVING count(*)>1;
SELECT user_id, title FROM repositories GROUP BY 1,2 HAVING count(*)>1;
SELECT program, level, faculty FROM (SELECT DISTINCT program, level, faculty, department FROM uni_programs) d GROUP BY 1,2,3 HAVING count(*)>1;
SELECT volunteer_task_id, user_id, array_agg(id) FROM volunteer_task_joins WHERE active GROUP BY 1,2 HAVING count(*)>1;  -- only the known pair 301, 302
SELECT user_id, space_id FROM staff_spaces GROUP BY 1,2 HAVING count(*)>1;
SELECT count(*) FROM design_days;                -- at most 1
SELECT count(*) FROM printer_sessions WHERE printer_id IS NULL;
SELECT job_task_quote_id, job_option_id FROM job_task_quote_options GROUP BY 1,2 HAVING count(*)>1;
SELECT b.id FROM sub_space_bookings b WHERE (SELECT count(*) FROM sub_space_booking_statuses s WHERE s.sub_space_booking_id = b.id) <> 1 OR NOT EXISTS (SELECT 1 FROM sub_space_booking_statuses s WHERE s.id = b.sub_space_booking_status_id AND s.sub_space_booking_id = b.id AND s.booking_status_id IS NOT NULL);  -- bookings without exactly one status row linked both ways
SELECT max(version) FROM schema_migrations;      -- expected to be 20261106200000; confirm before the merge
```

- [ ] Run the read-only lists and read them: `bin/rails memberships:pending_duplicates`, `bundle exec rake volunteer_awards:duplicates` and `Membership.stale_pending.count` in a console (see "Pending membership duplicates" and the `membership_expiry` note under "Scheduled tasks").
- [ ] **TODO (owner decision pending): the first run of `membership_expiry`.** The job is new in this release and first runs at the first 4am after the deploy. That run closes every pending checkout untouched for 7 days at once, with no cap, including the duplicate pending rows that have not been reviewed yet. Decide before merging whether it ships as is, ships with a cap, or is held for this release (commented out of `config/recurring.yml`), and replace this item with the decision.
- [ ] Check that every staff account (and every shared kiosk account) is assigned to the spaces it works in (Admin > Users > staff spaces). From this release staff can only switch to and work in their assigned spaces, and a saved space they are not assigned to is no longer used.
- [ ] Release the staff app version that sends an `Idempotency-Key` header on the same day (see "Deploy step: API idempotency keys").

### During and right after the deploy

- [ ] Check that `web` came up (`docker compose -f docker-compose.production.yml ps`, and `logs web` for the migration output). The migrations of this release take under a minute on a copy of a recent backup.
- [ ] Run `bookings:reconcile_statuses` exactly once, with `DEPLOYED_AT` set to the new `web` container's `Created` time, and read the list it prints (see "Deploy step: booking status column", step 2).
- [ ] Reload the staff dashboards that were open before the deploy (also on kiosks and shared screens). Their live table updates use a stream name that now includes the language, so an open page stops getting updates until it is reloaded.
- [ ] In the first hour, check the worker logs (`docker compose -f docker-compose.production.yml logs worker`) and the `job_alerts` inbox. The worker is recreated alongside `web`, so a scheduled job can run once before the migrations have finished and fail. Check that such a failure does not repeat after `web` is up.
- [ ] Create a training session and change space from the staff app.

### Rollback limits

Redeploying the previous image does not undo the migrations, and once some new data has been written the old code cannot read it. Do not roll the code back past this release after any of these has happened; fix forward instead, or restore the backup taken before the deploy:

- a key request has been denied (status 3, which older code does not know; see "Deploy step: key request denial reason");
- the repeat-rule migration has run: older code cannot read the Toronto form of a rule (see "Repeat rules stored in Toronto time");
- a volunteer has left a task, or staff removed someone, with the new code: the join state and its actor exist nowhere else, and older code does not keep the state up to date (see "Deploy step: volunteer task join state");
- a booking access request has been declined or revoked: older code reads only `approved`, so it shows those requests as pending again (see "Deploy step: booking access request status").

Rolling a migration back by hand (`db:migrate:down`) is possible for most of them, but several refuse once the new data exists, as their sections say, and a `change` migration that adds columns or tables drops their data on the way down. Export the data first.

## Scheduled tasks

Scheduled tasks run in the `worker` container (`bundle exec rake solid_queue:start`), from `config/recurring.yml`, in the application time zone (Eastern). Apart from the year-of-study bump (see below), nothing is scheduled with cron any more. The file has a block shared by production and staging, plus a block for each: the monthly CDEL report is production only, and the Google Calendar catch-up sync is staging only. The shared block also queues again, every 15 minutes, the Google Calendar pushes and removals of events that were never confirmed (rows of `google_calendar_pending_changes`; `GoogleCalendar::PendingChange.all` lists what is waiting, and rows that were resent five times stay there after a report, for staff to look at). The migration that creates that table only adds a table. A volunteer shadowing shift's Google event is created the same way (row action `shadow_push`, naming the shadowing hour): the shift is saved with its row, `GoogleCalendar::ShadowingPushJob` creates the event under the shift's stored id (an id Google already has counts as created), and an event that is not created is queued again by the same resend, up to five times, then reported. The migration that adds the shadowing hour to that table (nullable columns, a wider check, an index that also covers the new column) changes no existing row; rolling it back refuses to run while `shadow_push` rows are waiting, and deletes none. If the `worker` container is not running, nothing is scheduled. Starting it again resumes the schedule; runs missed while it was down are not made up. Solid Queue records each tick once, so restarting the worker during a deploy does not run a task twice.

Development does not run this schedule: it uses the `:async` job adapter, which runs jobs on a thread in the process that queued them, and `config/recurring.yml` has no `development` block. The README ("Background jobs in development") says how to run Solid Queue locally.

Locker checkout drafts that no rental points at (an abandoned checkout, or a crash between creating the draft on Shopify and storing its id) are closed by the same hourly job as the job-order drafts, `job_order_draft_sweep` (`JobOrderDraftSweepJob` runs `JobOrder::DraftSweep` and then `LockerRental::DraftSweep`; each reports its own problems and one never stops the other). A locker draft now carries the tags `makerepo_locker` (with the environment prefix) and `locker_rental:<id>`. The sweep lists the open drafts with that environment's locker tag that are older than an hour and have exactly one marker, and under the rental's row lock keeps the draft a rental waiting for payment stores, and otherwise deletes it on Shopify (never one Shopify reports paid) and forgets the stored id if it was that draft. No rental row is deleted or changed otherwise. A draft with no marker (every locker draft made before this change) is never touched, so those older drafts stay open until staff close them in Shopify; there is no way to count them without asking Shopify. If more than 200 drafts would be deleted in one run, nothing is deleted and the run is reported (the same kill switch as job orders; `LockerRental::DraftSweep.run(max_deletes: n)` in a console lifts it once the database has been checked). The run is safe to repeat.

Old locker drafts made before the marker existed (open, with the environment's locker tag, no `locker_rental:` tag, that no rental stores and that are older than 24 hours) are listed by `bin/rails lockers:untagged_drafts`, run in the `web` container (`docker compose -f docker-compose.production.yml exec web bin/rails lockers:untagged_drafts`). With no argument it only lists (`would close: <draft id>` per draft) and changes nothing, calls nothing but a read of Shopify's open drafts, and has no cap. After the maintainers approve the list, `bin/rails "lockers:untagged_drafts[apply]"` closes exactly those drafts on Shopify (printing `closed: <draft id>` for each, as the audit trail; the check that no rental stores a draft is made again inside the transaction that deletes it): a draft any rental stores, a paid draft, a draft with a marker, and another environment's draft are never touched, no rental row changes, more than 200 deletions in one run delete nothing (`CONFIRM_MAX_DELETES=n` lifts it after the database has been checked), and a second run changes nothing (a draft Shopify no longer has counts as cleared). Each unresolved draft or run problem (the cap included) is printed to standard error as `not resolved: <line>`, also when Ruby warnings are turned off (`RUBYOPT=-W0`). Exit codes: 0 resolved, 1 something unresolved, 2 another sweep is running.

Membership checkouts left unpaid are closed by `membership_expiry` (daily at 4am, `MembershipExpiryJob`): a pending membership with no checkout activity for `Membership::Expiry::STALE_AFTER` (7 days; the row's `updated_at`, which buying again also moves) has its Shopify draft order deleted and is marked `expired`; the row is kept. A membership whose draft is paid is never touched, and a Shopify error leaves the row pending for the next run (it is reported). The run is safe to repeat. To see what is waiting: `Membership.stale_pending.count`. Its first run after the release that adds it closes everything already stale in one go; see the TODO under "Before merging to master".

Check that tasks ran, in a Rails console (`docker compose -f docker-compose.production.yml exec web bin/rails console`):

```ruby
SolidQueue::RecurringTask.pluck(:key, :schedule)             # what is loaded
SolidQueue::RecurringExecution.order(run_at: :desc).limit(20).pluck(:task_key, :run_at)  # recent ticks
SolidQueue::FailedExecution.order(created_at: :desc).limit(5).pluck(:error)               # failures
```

The same data is in the `solid_queue_recurring_executions` and `solid_queue_failed_executions` tables, and the worker's logs (`docker compose -f docker-compose.production.yml logs worker`) show each job. Finished jobs are cleared out regularly, so check the recurring executions or the data a task writes (for example `PopularHour.maximum(:updated_at)`).

### Deploy step: remove the moved tasks from the host crontab

The host crontab still has `docker compose exec -T web` lines for these tasks (the containers have no cron of their own). They have not taken effect since 2026-08-31; `/var/www/makerrepo/log/cron_log.log` shows why. In the same deploy, remove the lines for the moved tasks (`crontab -e`) rather than fixing them: after this ships they run in the `worker` container, and a crontab line that starts working would run the task a second time (the CDEL report mailed twice, the popular hours counted twice).

Tasks that moved: popular hours, active volunteers, clear printers, the CDEL report, the Google Calendar webhook registration, and the locker expiry notices if a line for them exists. The print order reminder is removed (task and mailer method), so delete its line too. The year-of-study tasks (`increment_year:increment_one_year` and `increment_year:fix`) are removed as well (see the next section), so delete the `increment_year` line too.

### Deploy step: year of study counted from a reference point

The release that adds `users.year_of_study_entered`, `year_of_study_set_on` and `year_of_study_set_by` (migration `20261114100000`) stops moving the year of study up in place. The app counts the current year from the year as entered and the day it was set: a student moves up one year on the first day of the month their account was created in (local time), every year after the year it was created, up to year 8, then becomes Alumni. `users.year_of_study` is kept as it is and is no longer moved up; a form save still writes it. Reports outside the app should read the current year from the read-only view `reporting_user_years` (`user_id`, `year_of_study`, `year_of_study_entered`, `year_of_study_set_on`, `year_of_study_set_by`).

- The migration copies `year_of_study` into `year_of_study_entered` and dates it from the last run of the old task that changed the account: 2026-08-01 for accounts with `active` true (the crontab lines stopped working after 2026-08-31, and the runs of September to November 2026 changed nothing), and the last run before the account was marked inactive (2023-02-20 to 2023-03-05) for the others. `year_of_study_set_by` records which rule set each row (`backfill_last_run`, `backfill_marked_inactive`; `entered` once a person sets the year). So the September to November 2026 moves the task missed are counted, and the accounts it stopped moving in 2023 move up again.
- Before the deploy, confirm in `/var/www/makerrepo/log/cron_log.log` that the task has not run since 2026-08-01. The migration stops, changing nothing, if the data shows a scheduled run after that day; then set `LAST_TASK_RUN` in the migration to the last run and rehearse again.
- In the same deploy, remove the `increment_year` line from the host crontab (`crontab -e`). Read it first with `crontab -l`. The task no longer exists, so a line left behind only fails.
- `down` drops the view and the three columns, which restores the table exactly.
- The view's SQL is `db/views/reporting_user_years_v01.sql`, managed by the `scenic` gem (`create_view` in the migration and in `db/schema.rb`, so `db:schema:load` builds it too). A change to the view is a new version file (`_v02.sql`) and an `update_view` migration; dropping or changing the type of a column the view reads needs the view dropped and recreated in the same migration.

The locker notices migration must run before the first 8:30am run of the locker expiry notices (`locker_expiry_notices`). It marks the rentals that expired long ago as already notified, so renters are not mailed about old expiries. Running the migrations as part of the deploy covers this.

Post-deploy step for this release (Google Calendar webhook): run `bin/rails runner 'GoogleCalendar::WebhookRegistrar.register!'` once, right after the deploy. Channels registered before this release have no token, and the webhook refuses their pushes (401) until they are re-registered; there is no grace period for them. The same applies whenever `secret_key_base` is rotated: every channel's token is derived from it, so every channel is refused until it is re-registered with the same command.

### Deploy step: key request denial reason

The release that adds `key_requests.denial_reason` (migration `20261110120000`) adds one nullable text column and changes no row. Key requests gain a fourth status, `denied`, stored as the integer 3; the existing statuses keep 0, 1 and 2. Code from before the release cannot read a denied request (it fails on the unknown status), so deploy `web` and `worker` together, as usual, and do not roll back to the old code once a request has been denied. Rolling the migration back refuses while any request is denied or has a stored reason, naming the counts; export those rows and clear them first.

### Deploy step: one price per quote option

The release that adds `index_job_task_quote_options_on_quote_and_option` (unique over job task quote and job option) needs no manual step; `web` runs the migration on boot. It first looks for a quote with more than one row for the same option; if any exist it changes nothing and stops with a message listing the key and the row ids. Settle those rows by hand (decide with the maintainers which price stands), then deploy again. The latest audited backup held 75 rows and no duplicates. The index is built concurrently, and `down` only drops the index and keeps every row. The quote form already looks the row up before saving, and the model refuses a second row with a validation error.

### Deploy step: user language column

The release that adds `users.locale` needs no special order or backfill. The migration adds a nullable column with no default (existing users stay NULL, meaning no language chosen, and receive mail in English) and a check constraint allowing only `en`, `fr` or NULL. `down` drops the constraint and the column and touches no other data. A user's value is saved when they pick a language while signed in.

### Deploy step: booking status column

The release that adds `sub_space_bookings.booking_status_id` copies each booking's status into it when the migration runs, and from then on the app reads only that column, and the release that follows stops writing the old status rows (they stay as history, and deleting a booking still removes its own). Old code writes a status only to the old status table (the old `web` and `worker` containers run it until compose has replaced them), which would leave the column empty or stale. The deploy recreates `web` and `worker` together, and the worker does not need to be stopped first; the reconcile below copies over any status the old code wrote. So deploy in this order:

1. Deploy as usual (`web` runs the migrations on boot). The migration stops, changing nothing and listing booking ids, if a booking does not have exactly one status row linked both ways; fix those rows first (the booking status query under "Before merging to master" lists them).
2. Check that compose has replaced `web` and the old `web` container is stopped (`docker compose -f docker-compose.production.yml ps`). Read the time the new release was created with `docker inspect -f '{{.Created}}' $(docker compose -f docker-compose.production.yml ps -q web)`; `ps -q web` must print exactly one container id. Use `Created`, not `State.StartedAt`: a later restart of `web` moves the start time, and a too-late `DEPLOYED_AT` would let the task overwrite statuses the new release already changed. The time the deploy began also works, since an earlier time only protects more bookings. `DEPLOYED_AT` must end in `Z` or a zone offset; the task refuses a time without one. Then run, exactly once and right after the deploy, `docker compose -f docker-compose.production.yml exec -e DEPLOYED_AT=<that time, e.g. 2026-11-15T14:30:00Z> web bin/rails bookings:reconcile_statuses`. It refuses to run without `DEPLOYED_AT`. Where a booking's status differs from its old status row, it copies the old row's status into `booking_status_id`, records each change (booking, old value, new value) in `booking_status_reconciliations` in the same statement, and prints it. It never changes the old table. Old code wrote only the old rows, and the new release writes only the column and sets the booking's `updated_at` on every status change, so a booking that has a status and whose `updated_at` is after `DEPLOYED_AT` was changed by the new release: it is skipped and listed as changed by the new release after the deploy, and a late run therefore never undoes a newer status. Read that printed list after the run: a booking whose old row held a status written just before the switch, and that the new release then edited, is skipped too, so check each listed booking by hand against its old status row. A booking with no status is always copied. It also lists bookings that still have no status. A booking made or changed by this release has no old row, or an older one, and that is expected. Do not run it again: it is removed after this release.

To undo the reconcile, run `docker compose -f docker-compose.production.yml exec web bin/rails bookings:restore_reconciled_statuses` once, and only soon after the deploy. For each recorded change not yet restored, newest first, it sets the booking's `booking_status_id` back to the recorded old value, marks the record restored (`restored_at`, in the same statement) and prints the booking with the old and new value. A booking is left alone and listed if its column no longer holds the value the reconcile wrote (so a status changed since is kept; a later change back to the same value cannot be told apart and would be reverted) or if the booking was deleted; its older records are then left alone too. Running it again restores nothing more. The record table has no foreign key, so it outlives a deleted booking and the app never deletes it. Rolling the migration back refuses while the record table has rows (export the table, for example with `COPY ... TO`, and clear it first); with no rows it drops the new column and the record table. The old status table is untouched.

### Repeat rules stored in Toronto time

From this release the calendars write the start of a repeat rule (`events.recurrence_rule`, `staff_unavailabilities.recurrence_rule`) as Toronto wall-clock time (`DTSTART;TZID=America/Toronto:20270310T100000`) instead of a UTC stamp (`DTSTART:20270310T150000Z`). The app reads both forms the same way. Older releases cannot read the Toronto form, so rolling the code back past this release after rules have been saved needs those rules turned back into the UTC form first.

The migration `StoreRepeatRulesInTorontoTime` (20261109130000) rewrites the stored rules to the Toronto form. Its production run is approved, and like every migration it runs when the new `web` boots, so it runs with this release. What it does:

- It changes only the `DTSTART` line, and only when the Toronto wall time names the same instant (no reader takes the series start from this line, so the calendar feeds and Google see the same rule); a rule with two start lines, no `RRULE` line, a start that is not a date, or a start in the second 1:30 of the night the clocks go back is left as it is and named in the migration output (`<table> <id> left as it is: <reason>`). `updated_at` is not touched, and Google needs no new push (it only receives the `RRULE` and `EXDATE` lines, which do not change).
- Every rewrite is recorded in `recurrence_rule_rewrites` (table, row id, old text, new text, migration version). The output ends with `<table>: <n> of <m> rules with a start rewritten`.
- Rolling it back (`bin/rails db:migrate:down VERSION=20261109130000`) puts the recorded old text back, skips rows deleted since, and drops the record table. It refuses, changing nothing, while any rewritten rule has been edited since; the message gives the count. Those rules can be listed with `SELECT r.table_name, r.record_id FROM recurrence_rule_rewrites r JOIN events e ON r.table_name = 'events' AND e.id = r.record_id WHERE e.recurrence_rule IS DISTINCT FROM r.new_rule` (and the same with `staff_unavailabilities`).

Rehearsed on a copy of a recent backup: 344 rules (18 events, 326 unavailabilities), all rewritten, none left as they were; every rewritten rule gave the same start, feed text, Google lines and server occurrences; down restored the rules exactly (checksums of the rule and of every other column equal to before); a second up gave the same text; a down after one rule was edited refused and changed nothing.

### Deploy step: one dismissal per user and announcement

The release that adds the unique index on `announcement_dismisses (user_id, announcement_id)` needs no manual step; `web` runs the migration on boot. If any user has more than one dismissal row for the same announcement, the migration stops, changing nothing, and says how many pairs. Remove the extra rows by hand (they are exact repeats), then deploy again. Rolling back only drops the index.

### Deploy step: one pending volunteer hour per submission

The release that adds the partial unique index on `volunteer_hours (user_id, volunteer_task_id, date_of_task, total_time)` for rows with `approval IS NULL` needs no manual step; `web` runs the migration on boot. If a person already has two identical pending hours the migration stops, lists the ids and changes nothing; settle those rows by hand (staff can approve or reject one), then deploy again.

`bundle exec rake volunteer_awards:duplicates` lists, read only, the users who hold more than one task award (`cc_moneys` row) for the same task. It prints ids and changes nothing.

### Deploy step: one task award per user and task

The release that adds `index_cc_moneys_on_user_and_task_award` makes the database refuse a second `cc_moneys` row for the same user and volunteer task. `web` runs the migration on boot; it needs no manual step. The 2026-11-01 backup holds 8 user/task groups with 31 extra award rows (2 to 11 rows per group). Those old awards are kept: people may have spent them, and nothing is deleted, reversed or changed in amount. The migration adds `cc_moneys.legacy_duplicate` (default false), sets it true on every row after the first of each existing pair, and builds a partial unique index on `(user_id, volunteer_task_id)` for rows with a task that are not flagged. It prints each pair with the row it kept and the rows it flagged. If one of the extra rows was created after the migration started it stops, flags nothing and lists the ids. Balances are unchanged (`get_total_cc` still sums every row). Paying an award the index refuses counts as already paid: nothing is written and no hour is added. A deliberate admin re-award of the same task to the same user now needs a manual credit without a `volunteer_task_id`. `down` drops the index and the column, which restores the table exactly; re-running `up` flags the same rows. `rake volunteer_awards:duplicates` still lists the old pairs, flagged or not.

### Deploy step: claiming unclaimed CC Money

The release that adds `purchaser_email` and `claim_token_generation` to `cc_moneys` needs no manual step; `web` runs the migration on boot. It only adds the two columns (the generation starts at 0, the email empty) and changes no row; rolling back drops them.

From then on an unclaimed CC purchase can be claimed only by the signed-in account whose email equals the purchase email, and a mailed link expires after 30 days. Unclaimed rows bought before the release have no recorded purchase email, so their old links are refused. Nothing is lost: on `/admin/cc_moneys` an admin enters the buyer's address and presses Resend, which records the address, replaces earlier links and mails a new one. Resending a row always revokes the links sent before. Each resend that is sent is kept in `cc_money_claim_email_resends` (row, admin, address, time); those rows are only ever added. The release that adds that table needs no manual step (`web` runs the migration; rolling back drops the table, so export it first once resends exist).

The same page lets an admin correct the purchase email of an unclaimed row (a mistyped address): the new address replaces the stored one, every earlier link stops working and a new link is mailed to the new address. Each correction is kept in `cc_money_email_corrections` (row, admin, old address, new address, time); those rows are only ever added. The release that adds that table needs no manual step (`web` runs the migration; rolling back drops the table, so export it first once corrections exist).

### Deploy step: training skill lists clean-up

The release that adds `training_skill_list_changes` (migration `20261107100000`) and cleans the training skill lists (`20261107100100`) needs no manual step; `web` runs both on boot. The clean-up rewrites `trainings.list_of_skills_en` and `list_of_skills_fr` to one shape (names stripped, no blank items, joined with `, `). Only a value that differs from that shape is changed, and each change is recorded in `training_skill_list_changes` (training, column, old value, new value) in the same transaction; the output ends with `<n> lists rewritten` per column. On a copy of a recent backup it rewrote about 54 values (the table holds 36 trainings). Running it again changes nothing. The data cannot make it stop.

Verify afterwards (read only): `SELECT column_name, count(*) FROM training_skill_list_changes GROUP BY 1;` matches the counts in the migration output, and the training pages list the same skills as before.

Reversible: `down` of the clean-up puts every recorded old value back and marks the record restored, but only while each column still holds the value the migration wrote. If any was edited since, or its training is gone, it stops, changes nothing and names the training ids; settle those by hand first. The record table is never dropped, not even by `down` of `20261107100000`.

### Deploy step: legacy preferred locker text

The release that drops `locker_rentals.preferred_locker` (migration `20261107200000`) removes an old free-text column that was empty in every row and unused; the link to the preferred locker is `preferred_locker_id`, which stays. If any row holds text the migration stops, changes nothing and names the count, which stops the deploy. The first query under "Before merging to master" counts those rows. If it is not 0, copy that text somewhere safe (for example with `COPY (SELECT id, preferred_locker FROM locker_rentals WHERE preferred_locker <> '') TO ...`), decide with the maintainers what it means, clear it, then deploy again.

Verify afterwards (read only): `SELECT column_name FROM information_schema.columns WHERE table_name = 'locker_rentals' AND column_name = 'preferred_locker';` returns no row, and the locker rental pages show the preferred locker as before.

Reversible in shape only: `down` adds the column back as a nullable string with no default. There is nothing to restore, since the migration refuses to drop text.

### Deploy step: volunteer task join state

The release that adds `volunteer_task_joins.state`, `state_changed_at` and `state_changed_by_id` (migration `20261107210000`) and re-derives closed joins (`20261107220000`) needs no manual step; `web` runs both on boot. The first adds the columns (state `joined`, `completed`, `left` or `removed`, with a check constraint, a foreign key that is nullified when the user is deleted, and indexes) and fills the state from the old `active` flag: active is `joined`; otherwise `completed` when the user has an approved request for the task, and `removed` for the rest. Closed rows take their `updated_at` as the time of the change, and the actor stays empty. `active` is not touched. The second gives any row still marked `joined` with `active` false the state the same rules give, recording each change (join, old state and time, new state) in `volunteer_task_join_state_changes`. Neither can stop on the data.

Verify afterwards (read only): `SELECT state, active, count(*) FROM volunteer_task_joins GROUP BY 1,2 ORDER BY 1,2;` shows `joined` only with `active` true, and no other state with `active` true.

Reversible until the new code writes a state the old data cannot give back. `down` of `20261107220000` puts the recorded rows back and keeps its record table. `down` of `20261107210000` refuses, changing nothing, once any join has the state `left` or a recorded actor, because neither exists anywhere else. From then on, do not roll the code back past this release (see "Rollback limits").

### Deploy step: restored categories and equipment

The release that restores the lost categories (migration `20261108000001`) needs no manual step; `web` runs it on boot. It puts back the categories of 35 project proposals and the category and equipment of one repository, which were lost between two earlier production backups. The rows are embedded in the migration (course codes and equipment names only). A proposal or repository that still exists and still has no categories (or no equipment) gets its rows; one that has rows since, or no longer exists, is left alone, and no existing row is updated or deleted. Every inserted row is recorded in `restored_rows` by the statement that inserts it. The output ends with `restored <n> rows; skipped ...`. Running it again inserts nothing. It cannot stop on the data.

Verify afterwards (read only): `SELECT table_name, count(*) FROM restored_rows GROUP BY 1;` (37 rows, 36 categories and 1 equipment, when every parent was still empty; fewer means some parents had rows by then, which the output lists as skipped), and the restored proposals show their course again.

Reversible while the rows are untouched: `down` deletes exactly the recorded rows, and only if every one still has the parent, name and `updated_at` it was inserted with; otherwise it stops, changes nothing and keeps `restored_rows`. It drops `restored_rows` only when no record is left in it.

### Deploy step: booking access request status

The release that adds `user_booking_approvals.status`, `decided_by_id`, `decided_at` and `reason` (migration `20261109120000`) needs no manual step; `web` runs it on boot. Declined and revoked requests are kept with a status instead of being deleted. The migration sets each existing row's status from `approved` (true is `approved`, anything else `pending`), adds a check constraint on the four statuses and an index, and leaves `approved` and `staff_id` as they are; the model keeps `approved` equal to "status is approved". Existing rows get no decider, time or reason. It cannot stop on the data.

Verify afterwards (read only): `SELECT status, approved, count(*) FROM user_booking_approvals GROUP BY 1,2;` shows `approved` only with `approved` true and `pending` only with false or NULL, and the admin booking page lists the same pending and approved requests as before.

Reversible until a decision is recorded: `down` refuses, naming the counts and changing nothing, once any request is declined or revoked, has a decider, time or reason, or has a status that differs from `approved`. Older code shows declined and revoked requests as pending, so do not roll the code back once staff have declined or revoked one.

### Deploy step: rooms with bookings cannot be deleted

The release that changes the foreign key from `sub_space_bookings.sub_space_id` to `sub_spaces` from cascade to restrict (migration `20261110090000`) needs no manual step; `web` runs it on boot. Until now deleting a room also deleted its bookings. From this release the admin page refuses to delete a room that has bookings and says why, and the database refuses a direct delete as well. The migration changes only the constraint (it validates the existing rows, which already satisfy it), so it cannot stop on the data.

Verify afterwards (read only): `SELECT confdeltype FROM pg_constraint WHERE conrelid = 'sub_space_bookings'::regclass AND confrelid = 'sub_spaces'::regclass;` returns `r` (restrict; `c` was cascade).

Reversible: `down` restores the cascade exactly. A room that has to go now needs its bookings settled first; nothing deletes them for it.

### Deploy step: one repository title per owner

The release that adds `index_repositories_on_user_id_and_title` (unique over owner and title, migration `20261112150000`) needs no manual step; `web` runs it on boot. It makes the database refuse a second repository with the same title for the same owner, hidden repositories included and case-sensitive, the rule the model validation already applies. If an owner already holds a title twice, the migration stops, changes nothing and lists the titles and row ids, which stops the deploy; the query under "Before merging to master" finds them first. Settle those rows by hand with the maintainers (for example by renaming one), then deploy again. A copy of a recent backup had no duplicates, deleted rows included. The index is built concurrently, so it waits for open transactions.

Verify afterwards (read only): `SELECT indexdef FROM pg_indexes WHERE indexname = 'index_repositories_on_user_id_and_title';` returns one row. An interrupted build leaves an invalid index of that name; the next run of the migration drops and rebuilds it.

Reversible: `down` only drops the index and keeps every row.

### Deploy step: membership status default

The release that changes the column default of `memberships.status` from `paid` to `pending` (migration `20261113110000`) needs no manual step; `web` runs it on boot. The model has always created memberships as pending; only a row inserted without a status (raw SQL, `insert_all`) used the column default, and would have counted as paid. No existing row is read or written, and it cannot stop on the data.

Verify afterwards (read only): `SELECT column_default FROM information_schema.columns WHERE table_name = 'memberships' AND column_name = 'status';` names `pending`.

Reversible: rolling it back sets the default to `paid` again and changes no row.

### Deploy step: API idempotency keys

The release that creates `api_idempotency_keys` (migration `20261113120000`) needs no manual step; `web` runs it on boot. From this release `POST /api/v1/training_sessions` needs an `Idempotency-Key` header: a repeat of the same request with the same key gets the first answer instead of creating a second session, and the same key with a different request is refused (see `doc/api/v1/`). Each key is stored with its user, a digest of the request and the answer given. Release the staff app version that sends the header on the same day; until then, creating a training session from the app is refused with `idempotency_key_required`. Rows are never pruned: they are small, and an old row only answers a repeat of its own submission. A user's rows are deleted with the user. The migration only creates the table.

Verify afterwards (read only): after a session is created from the staff app, `SELECT count(*) FROM api_idempotency_keys;` is at least 1.

Reversible: rolling it back drops the table and its rows, after which a repeated request can create twice. Export the table first if it is needed.

### Deploy step: uOEng profiles

The release that creates `uoeng_profiles` (migration `20261113150000`) needs no manual step; `web` runs it on boot. Each uOEng profile record holds the latest answer the uOEng student-information service gave about a user, one record per user (a unique index on `user_id`, so a card tap and a staff check at the same time write one record). The user's own fields are never changed by it. Faculty reports and the new users report show the faculty from the uOEng profile record where there is one, and the user's own faculty otherwise. A uOEng profile record is deleted with its user. The migration only creates the table.

Verify afterwards (read only): `SELECT source, count(*) FROM uoeng_profiles GROUP BY 1;` grows as members tap in or staff run the faculty membership check.

Reversible: rolling it back drops the table and every uOEng profile record; reports then show the users' own faculty, and the next check after a redeploy fetches the answers again.

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

The report mailed on the 1st covers the month just ended. A month is mailed once: a run first claims `cdel_report_sent:YYYY-MM` in the `settings` table (value `claimed:<time>`), sends the mail, and then sets the value to `sent`, so a second run of the same month (the scheduled task run again, or the commands below) mails nothing. A run whose delivery fails hands its claim back and can be repeated. A run killed in the middle (worker stopped, crash) leaves its `claimed:` value; runs started within 30 minutes skip the month, and after that the next run takes the claim over and sends it (if the crash came right after the mail was sent, the month is mailed twice). To clear a stuck claim at once, run `Setting.where(key: "cdel_report_sent:2026-10").update_all(value: nil)` in a console, then repeat the run. To mail a month that was missed, give the month as `YYYY-MM` (not later than the current month); to mail a month again that was already sent, add `FORCE=1`. Each run sends one mail:

```
docker compose -f docker-compose.production.yml exec web bin/rails "reports:send_cdel_report_to_sharepoint[2026-08]"
docker compose -f docker-compose.production.yml exec web bin/rails "reports:send_cdel_report_to_sharepoint[2026-09]"
docker compose -f docker-compose.production.yml exec web bin/rails "reports:send_cdel_report_to_sharepoint[2026-10]"
docker compose -f docker-compose.production.yml exec -e FORCE=1 web bin/rails "reports:send_cdel_report_to_sharepoint[2026-10]"
```

The last line mails October again even though it was sent.

From a console, `CdelReportJob.perform_later(month: "2026-08")` does the same, and `force: true` mails the month again.

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

### Pending membership duplicates (read only)

One open checkout per member and tier is enforced by the member's row lock, not by the database, so older data can hold more than one pending membership for a pair. `bin/rails memberships:pending_duplicates` lists each such member and tier pair with the number of pending rows and their ids, then one line per row: its created and last updated time (a reused checkout is touched, so the latest update shows which draft was handed out most recently), the Shopify draft id stored on it (or none) and whether it is the row kept (the lowest id, the one a new purchase serves) or an extra. It only reads: it changes no row and calls no outside service. Run it in the `web` container (`docker compose -f docker-compose.production.yml exec web bin/rails memberships:pending_duplicates`). Before closing any draft, check each extra draft's state in Shopify: an extra row may hold the draft the member was last sent. Closing the extra drafts and adding a unique index are separate steps that need the maintainers' approval after this list has been reviewed.

### Like and vote counters

`repositories.like` and `comments.upvote` are stored numbers that `Like.give`, `Like.take_back`, `Upvote.cast`, `Upvote.switch` and `Upvote.retract` change together with the row; they should equal the number of likes of the repository and the upvotes minus the downvotes of the comment. Older rows can differ (a like or vote removed or moved by a console command or a user merge did not always move the counter). To see the differences, which changes nothing, then to correct them (owner step, run when the site is quiet and check the list first):

```
docker compose -f docker-compose.production.yml exec web bin/rails counters:recount
docker compose -f docker-compose.production.yml exec web bin/rails "counters:recount[apply]"
```

Applying locks each row that differs, counts its likes or votes again inside that transaction, sets the counter to that number and adds a row to the `counter_recount_corrections` table (table, row id, column, old value, new value, run time). That table is the permanent record of the old values and is only ever added to. A CSV of the same changes is also written to `tmp/counter_recount_<time>_<random>.csv` in the `web` container as a convenience (never overwritten, replaced on the next deploy; copy it out with `docker compose -f docker-compose.production.yml cp web:/rails/tmp/<file> .` if wanted). Running the list again afterwards shows nothing. To undo, set each counter back to `old_value` from `counter_recount_corrections` for the run. No like, vote, repository or comment is changed or removed. The migration that creates the table only adds it; `down` drops that table.

## Job order chat: extra notification recipients

Every chat message on a job order is emailed, one email per person, to the order's owner, its assigned staff and everyone who has posted in that chat (never to its author). Besides those, the setting `chat_message_extra_recipients` lists extra people who are mailed about every message: user ids and plain email addresses, separated by commas, spaces or new lines. Until the setting is saved it holds the users who were always mailed (`25,1607`). In a Rails console:

```ruby
Setting.get("chat_message_extra_recipients")                       # nil means the default is in use
Setting.set("chat_message_extra_recipients", "25, 1607, desk@example.com")
Setting.set("chat_message_extra_recipients", "")                    # nobody extra
```

The change applies to the next message. A user id that no longer exists is skipped.

## Google Calendar: owner of imported events

The Google Calendar sync turns room events into bookings owned by the user whose email is the event creator's. When the creator has no account (or the event has no creator), the owner is the user whose email is in the setting `google_calendar_fallback_email`, else in the `GOOGLE_CALENDAR_FALLBACK_EMAIL` environment variable of the `web` and `worker` containers. The setting is optional, and there is no built-in address. Without it (or when the address names no user), a new event from an unknown creator is imported with no owner: the booking still blocks the room and appears in the booking admin panel with an empty owner cell, but the room calendar does not show it. A booking that already has an owner keeps it when its event syncs again and resolves to nobody; the owner changes only when the sync resolves an account (the creator's, or the fallback). In a Rails console:

```ruby
Setting.get("google_calendar_fallback_email")                      # nil or "" means the environment variable, then nobody
Setting.set("google_calendar_fallback_email", "bookings@example.com")
```

A change applies to events created or changed after it: each sync of an event from an unknown creator then gives its booking the configured account. Nothing needs to be run on deploy.

## Deleted repositories and their files

Deleting a repository hides it (`repositories.deleted`); nothing is removed, and an admin can restore it from the admin page "Deleted Repositories". The photos and files of a hidden repository stop being served by the site (Active Storage links answer 404, except to a signed-in admin), but hiding is not a purge. Copies already cached by a browser or a CDN (proxy responses are public with a very long lifetime) and storage-service links already issued (valid for about five minutes) stay usable until they expire. The stored files stay in the storage service until someone removes them on purpose; the application never does so for a hidden repository. `repositories.hidden_reason` records why a repository is hidden (0 deleted by the owner or a member, 1 by an admin, 2 because its owner's account was deleted); restoring an account brings back only reason 2. Rows hidden before the column existed have a NULL reason and are treated as deleted on purpose, so only an admin restores them from "Deleted Repositories". If a file has to disappear for good, that is a separate manual step on the storage service and a CDN purge.

## Repository zip cache

Repository downloads are cached as zips in `tmp/repository_zips`. The cache is limited by `REPOSITORY_ZIP_CACHE_MAX_BYTES` (default 5 GB), the filesystem keeps `REPOSITORY_ZIP_MIN_FREE_BYTES` free (default 5 GB), and a zip larger than `REPOSITORY_ZIP_MAX_CACHED_ZIP_BYTES` (default 1 GB) is streamed instead of kept. An hourly job trims the cache (least recently used first) and removes partial zips older than an hour. Everything in `tmp/repository_zips` can be deleted at any time; zips are rebuilt on demand.

The cache lives in the `repository_zips` Docker volume (`staging_repository_zips` on staging), mounted at `/rails/tmp/repository_zips` in both the `web` and `worker` services, so it survives deploys and the hourly job manages the same files the web service writes. Emptying it is safe: `docker compose -f docker-compose.production.yml exec web sh -c 'rm -f /rails/tmp/repository_zips/*'` (or remove the volume). `df` inside the container measures the host filesystem behind the volume. If the free space cannot be read (unexpected `df` output) a request applies only the size cap, the problem is reported, and the hourly job evicts nothing that run.

## Help requests whose GitHub issue failed

When GitHub does not return an issue number, the help request is still saved and the sender is told it was not submitted. These rows have an empty `gh_issue_number`. Find them in a console with `Help.where(gh_issue_number: nil)`. A retry by the sender creates a new row; the earlier one stays as the record of the attempt. Nothing deletes these rows.

## Interface components

Repeated interface pieces are ViewComponents (`view_component` gem) in `app/components/`, named `<Thing>Component`. The directory is autoloaded like the other `app/` directories.

- A component's Stimulus controller lives in `app/javascript/controllers/`, named after the component (for example `key_request_deny_form_controller.js`), because the controller index only loads files under that directory. Its scoped CSS goes in a partial under `app/javascript/stylesheets/` imported by `application.scss`.
- Component specs live in `spec/components/` and get `type: :component`, the ViewComponent test helpers and Capybara matchers from `spec/support/view_component.rb`.

## Programs unique index

The release that adds `index_programs_on_user_id_and_program_type` makes the database refuse a second row for the same user and program (Development, Volunteer, Teams). The migration first checks for existing duplicates; if any exist it changes nothing and stops with a message listing the user and the ids of the duplicate rows, to be settled by hand before running it again. The 2026-11-04 backup had none. It builds the index concurrently, and `down` only drops the index and keeps every row. Joining a program (`Program.join`) is an insert that does nothing when the row exists and does not name the index, so code that runs before the migration (for example the `worker` container) still works.

## University programs import

Admins update the programs offered on the sign-up and profile forms by uploading a csv (columns `program,level,faculty,department`; the shipped file is `lib/assets/programs.csv`) on the admin University Programs page. The import never deletes rows. A program is identified by program, level and faculty: new ones are added, a changed department is updated in place, a retired program the file lists again is brought back, and active programs missing from the file are marked inactive (`uni_programs.active`) so the forms stop offering them while users' stored programs and `User#department` keep working. The whole file is applied in one transaction under a table lock; uploading the same file again changes nothing. The page reports how many programs were added, updated, restored and retired.

The release that adds `uni_programs.active` and `index_uni_programs_on_program_level_faculty_active` (unique over program, level and faculty, for active rows) marks the second copy of a row that is identical in every column inactive (the 2026-11-01 backup holds one such pair, "Microprogram Anthropocene"); it never removes or edits a row otherwise. If two rows share program, level and faculty but differ in department, the migration stops with a message listing them and changes nothing else; settle those by hand and run it again. `down` drops the index and the column and keeps every row; programs retired by imports after the release then look active again to the old code, because the flag is gone (the rows are kept). The admin University Programs page lists retired programs in a read-only "Retired programs" section.

## Volunteer task joins: one joined row per user and task

The release that adds `index_volunteer_task_joins_on_task_and_user_when_joined` (unique over task and user, for rows whose state is `joined`) makes the database refuse a second joined row for the same user and task, which the model validation could not guarantee for two simultaneous joins. Ended rows (completed, left, removed) are history and may repeat. A join that loses such a race gets the same message as the validation ("User is already on this task"). The migration needs no manual step; `web` runs it on boot. It first looks for (task, user) pairs with more than one joined row. If exactly one pair has exactly two, it ends the newer of the two (by created_at, then id): the row is kept with the state `removed`, `active` false, `state_changed_at` set and no actor, and its state before is written to `volunteer_task_join_duplicate_endings` (one row per change: join id, kept join id, old state, old `active`, old change time and actor, old `updated_at`, `restored_at`). The 2026-11-01 backup holds exactly that one pair (joins 301 and 302; 302 is ended). If any other joined duplicates exist (more than one pair, or a pair of three), the migration stops, lists the ids and changes nothing; settle them by hand and run it again. Running it again changes nothing. `down` drops the index first, then puts every recorded row back exactly as it was (only if it is still in the state the migration gave it) and marks the record restored. The record table is kept on `down`.

The release that adds `index_design_days_single_row` makes the database hold at most one `design_days` row, so two simultaneous first visits to the Design Day settings can no longer create two (the second visit now reads the first one's row). `web` runs the migration on boot. If `design_days` already has more than one row the migration stops, changes nothing and lists the ids; decide which row to keep and resolve the rest by hand, then deploy again. `down` only drops the index and keeps every row.

The release that makes `printer_sessions.printer_id` NOT NULL (migration `20261113100000`) needs no manual step; `web` runs the migration on boot. It first counts printer sessions with no printer; if any exist it changes nothing and stops with a message naming the count. Decide by hand what those rows stand for, then deploy again; the migration never deletes or changes a session. The 2026-11-01 backup had none. It adds a check NOT VALID, validates it without blocking writes, sets the column NOT NULL and drops the check; each step waits at most 3 seconds for its lock and is retried. `down` makes the column nullable again and changes no row.

## Imported calendar (ICS) cache

The body of each imported calendar link (staff external unavailabilities, a space's open-hours and needed-staff calendars) is kept in Solid Cache (`Rails.cache`, the `solid_cache_entries` table) for ten minutes, so a page load that reads the same link again does not fetch it again. Only a successful body is kept; a failed or empty fetch is read again on the next load. The body is encrypted with a key derived from the application secret (`secret_key_base`), and the cache key is a digest of the link, never the link (a private calendar link holds a secret). Emptying the cache is safe at any time (`Rails.cache.clear`, or delete one entry with `Rails.cache.delete(["ics-body", Digest::SHA256.hexdigest(url)])`): the next load fetches the link again. After the application secret is changed, copies made under the old secret cannot be read; a load that meets one reports the calendar as failed until the entry expires (at most ten minutes) or is cleared. Nothing needs to be run on deploy.

## Staff space unique index

The release that adds `index_staff_spaces_on_user_id_and_space_id` (unique over user and space) needs no manual step; `web` runs the migration on boot. It makes the database refuse a second assignment of one staff member to one space. The migration first looks for duplicates; if any exist it changes nothing and stops with a message listing the key and the row ids. Settle those rows by hand (keep one, decide with the maintainers what happens to the others), then deploy again. The 2026-11-01 backup had no duplicates. The index is built concurrently, and `down` only drops the index and keeps every row. A repeated insert that hits the index raises `ActiveRecord::RecordNotUnique`; the staff assignment form looks the row up first, so a repeat is the normal outcome.

## Kiosk sign-in log

Every kiosk sign-in or sign-out that changes something writes one row to `kiosk_sign_events` (actor, visitor, space, `sign_in` or `sign_out`, `created_at`) in the same transaction as the lab session change. A sign-in for someone already inside, an unknown visitor or space, and a request with neither action write nothing. Rows are append-only (the model refuses updates and deletes). They are kept one year: `KioskSignEventCleanupJob` (recurring `kiosk_sign_event_cleanup`, daily at 3:15am) deletes rows older than a year in batches with a relation-level delete; running it again deletes nothing more. The table is not read by Power BI. There is no page for it; read it from the Rails console, for example `KioskSignEvent.newest_first.includes(:actor, :visitor, :space).limit(50)`. The migration only creates the table, so it needs no manual step.
