# frozen_string_literal: true

# The year of study becomes a reference point (the year as entered and the day
# it was set) from which the current year is counted (User::YearOfStudy), and
# the read-only view reporting_user_years gives reports outside the app the
# current year counted the same way.
#
# Additive only: users.year_of_study is not changed. The backfill copies it into
# year_of_study_entered and sets the reference day to the day the old monthly
# task last changed that account's year, recording in year_of_study_set_by which
# rule set it:
# - backfill_last_run: accounts the task still moved up (users.active true).
#   The task last took effect on 2026-08-01 (the server crontab stopped working
#   after 2026-08-31; the backup of 2026-11-01 has no change from the runs of
#   September, October or November), so the reference day is the last first of
#   the creation month on or before 2026-08-01.
# - backfill_marked_inactive: accounts the task skipped because they were marked
#   inactive (users.active false). They were marked between 2023-02-20 and
#   2023-03-05 (most on 2023-02-20 and 2023-02-22), so the reference day is the
#   last first of the creation month on or before the day the row was last
#   written, when that is no later than 2023-03-05, and otherwise on or before
#   2023-02-22.
# In both, an account with no such day after its creation year keeps its
# creation day: the task never changed it.
#
# down drops the view and the three columns; users.year_of_study was never
# written, so that restores the table exactly.
class AddYearOfStudyReferenceToUsers < ActiveRecord::Migration[8.1]
  LAST_TASK_RUN = "2026-08-01"
  MARKING_ENDED = "2023-03-05"
  MAIN_MARKING = "2023-02-22"
  ZONE = "America/New_York"
  LOCAL_TODAY = "((now() AT TIME ZONE '#{ZONE}'))::date"
  STUDENTS = "'grad', 'undergrad', 'international_grad', 'international_undergrad'"
  SET_BY = "'entered', 'backfill_last_run', 'backfill_marked_inactive'"
  # A scheduled run of the old task wrote many students created in the month of
  # the run in the first hour of its first day; a few such rows are sign-ins.
  RUN_AFTER_LAST_THRESHOLD = 10

  def local(column) = "((#{column} AT TIME ZONE 'UTC') AT TIME ZONE '#{ZONE}')"

  VIEW_SQL = <<~SQL
    CREATE VIEW reporting_user_years AS
    SELECT users.id AS user_id,
      CASE
        WHEN moves.n = 0 OR users.year_of_study_entered IS NULL OR users.year_of_study_entered = 'Alumni'
          THEN users.year_of_study_entered
        WHEN entered.year BETWEEN 1 AND 7 AND entered.year + moves.n <= 8 THEN (entered.year + moves.n)::text
        ELSE 'Alumni'
      END AS year_of_study,
      users.year_of_study_entered,
      users.year_of_study_set_on,
      users.year_of_study_set_by
    FROM users
    CROSS JOIN LATERAL (
      SELECT (users.created_at AT TIME ZONE 'UTC') AT TIME ZONE '#{ZONE}' AS created,
             #{LOCAL_TODAY} AS today
    ) here
    CROSS JOIN LATERAL (
      SELECT CASE WHEN users.identity IN (#{STUDENTS}) THEN GREATEST(0,
        EXTRACT(YEAR FROM here.today)::int
          - CASE WHEN EXTRACT(MONTH FROM here.created) > EXTRACT(MONTH FROM here.today) THEN 1 ELSE 0 END
          - GREATEST(
              EXTRACT(YEAR FROM users.year_of_study_set_on)::int
                + CASE WHEN EXTRACT(MONTH FROM here.created) > EXTRACT(MONTH FROM users.year_of_study_set_on) THEN 0 ELSE 1 END,
              EXTRACT(YEAR FROM here.created)::int + 1)
          + 1)
      ELSE 0 END AS n
    ) moves
    CROSS JOIN LATERAL (
      SELECT COALESCE(substring(users.year_of_study_entered FROM '^[0-9]+')::numeric, 0) AS year
    ) entered
  SQL

  def up
    refuse_when_the_task_ran_after_its_last_known_run
    add_column :users, :year_of_study_entered, :string
    add_column :users, :year_of_study_set_on, :date
    add_column :users, :year_of_study_set_by, :string
    execute backfill_sql
    change_column_null :users, :year_of_study_set_on, false
    change_column_null :users, :year_of_study_set_by, false
    # A row written without the app's writer (User::YearOfStudy) was set on the
    # day it was inserted.
    change_column_default :users, :year_of_study_set_on, -> { LOCAL_TODAY }
    change_column_default :users, :year_of_study_set_by, "entered"
    add_check_constraint :users, "year_of_study_set_by IN (#{SET_BY})", name: "users_year_of_study_set_by_known"
    execute VIEW_SQL
  end

  def down
    execute "DROP VIEW reporting_user_years"
    remove_check_constraint :users, name: "users_year_of_study_set_by_known"
    remove_column :users, :year_of_study_set_by
    remove_column :users, :year_of_study_set_on
    remove_column :users, :year_of_study_entered
  end

  private

  # The reference days above assume the task has not run since LAST_TASK_RUN.
  def refuse_when_the_task_ran_after_its_last_known_run
    count = select_value(<<~SQL).to_i
      SELECT count(*) FROM users
      WHERE active AND identity IN (#{STUDENTS})
        AND updated_at >= (DATE '#{LAST_TASK_RUN}' + INTERVAL '1 month')
        AND EXTRACT(DAY FROM #{local('updated_at')}) = 1 AND EXTRACT(HOUR FROM #{local('updated_at')}) = 0
        AND EXTRACT(MONTH FROM #{local('updated_at')}) = EXTRACT(MONTH FROM #{local('created_at')})
    SQL
    return if count < RUN_AFTER_LAST_THRESHOLD

    raise "The year-of-study task seems to have run after #{LAST_TASK_RUN} (#{count} students written in the first " \
          "hour of the first day of their creation month). Find its last run in the cron log, set LAST_TASK_RUN to " \
          "it and rehearse again."
  end

  def backfill_sql
    <<~SQL
      WITH ref AS (
        SELECT id, #{local('created_at')} AS created,
          CASE WHEN active THEN DATE '#{LAST_TASK_RUN}'
               WHEN #{local('updated_at')}::date <= DATE '#{MARKING_ENDED}' THEN #{local('updated_at')}::date
               ELSE DATE '#{MAIN_MARKING}' END AS last_run,
          CASE WHEN active THEN 'backfill_last_run' ELSE 'backfill_marked_inactive' END AS set_by
        FROM users
      ), moved AS (
        SELECT id, created, set_by,
          EXTRACT(YEAR FROM last_run)::int
            - CASE WHEN EXTRACT(MONTH FROM created) > EXTRACT(MONTH FROM last_run) THEN 1 ELSE 0 END AS move_year
        FROM ref
      )
      UPDATE users SET
        year_of_study_entered = users.year_of_study,
        year_of_study_set_on = CASE WHEN moved.move_year > EXTRACT(YEAR FROM moved.created)
                                    THEN make_date(moved.move_year, EXTRACT(MONTH FROM moved.created)::int, 1)
                                    ELSE moved.created::date END,
        year_of_study_set_by = moved.set_by
      FROM moved WHERE moved.id = users.id
    SQL
  end
end
