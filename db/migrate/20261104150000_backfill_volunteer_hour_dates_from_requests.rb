# Hours created by approving a completion request were saved without a date_of_task,
# the day the work was done. That day is when the volunteer reported the task done:
# the created_at of the completion request. This fills the blank dates from the
# latest approved request of the same user and task that was created at or before
# the hour (the hour is created at approval, so the request always comes first).
#
# Only rows with a blank date are touched, and only when such a request exists; rows
# with a date, and blank rows without a matching request, are left as they are. The
# ids that were filled are kept in volunteer_hour_date_backfills, so down can blank
# exactly those rows again and nothing else. Safe to run again: filled rows no longer
# match, and the id table is created only once.
class BackfillVolunteerHourDatesFromRequests < ActiveRecord::Migration[8.1]
  TABLE = "volunteer_hour_date_backfills"

  MATCH = <<~SQL.squish
    SELECT r.created_at
    FROM volunteer_task_requests r
    WHERE r.user_id = h.user_id
      AND r.volunteer_task_id = h.volunteer_task_id
      AND r.approval = TRUE
      AND r.created_at <= h.created_at
    ORDER BY r.created_at DESC, r.id DESC
    LIMIT 1
  SQL

  def up
    execute <<~SQL.squish
      CREATE TABLE IF NOT EXISTS #{TABLE} (
        volunteer_hour_id integer PRIMARY KEY,
        filled_at timestamp without time zone NOT NULL DEFAULT now()
      )
    SQL

    filled = select_rows(<<~SQL.squish)
      WITH filled AS (
        UPDATE volunteer_hours h
        SET date_of_task = (#{MATCH})
        WHERE h.date_of_task IS NULL
          AND EXISTS (#{MATCH})
        RETURNING h.id
      )
      INSERT INTO #{TABLE} (volunteer_hour_id)
      SELECT id FROM filled
      ON CONFLICT (volunteer_hour_id) DO NOTHING
      RETURNING volunteer_hour_id
    SQL
    left_blank = select_value("SELECT COUNT(*) FROM volunteer_hours WHERE date_of_task IS NULL").to_i
    say "volunteer_hours: #{filled.size} dates filled from completion requests, #{left_blank} still blank"
  end

  # Roll back 20261104150100 (the date_of_task check) first: this down sets the filled dates back to
  # NULL, which that check rejects even while NOT VALID. A normal rollback runs them in that order.
  def down
    execute <<~SQL.squish
      UPDATE volunteer_hours SET date_of_task = NULL
      WHERE id IN (SELECT volunteer_hour_id FROM #{TABLE})
    SQL
    execute "DROP TABLE IF EXISTS #{TABLE}"
  end
end
