# Hours created by approving a completion request were saved without a date_of_task,
# the day the work was done. That day is when the volunteer reported the task done:
# the created_at of the completion request. This fills the blank dates from the
# latest approved request of the same user and task that was created at or before
# the hour (the hour is created at approval, so the request always comes first).
#
# Only rows with a blank date are touched, and only when such a request exists; rows
# with a date, and blank rows without a matching request, are left as they are. The
# ids that were filled, and the date written to each, are kept in volunteer_hour_date_backfills,
# so down can blank exactly those rows again, and only while they still hold the date written
# (an hour edited since keeps its date). Safe to run again: filled rows no longer
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
        filled_at timestamp without time zone NOT NULL DEFAULT now(),
        filled_value timestamp without time zone
      )
    SQL
    execute "ALTER TABLE #{TABLE} ADD COLUMN IF NOT EXISTS filled_value timestamp without time zone"

    filled = select_rows(<<~SQL.squish)
      WITH filled AS (
        UPDATE volunteer_hours h
        SET date_of_task = (#{MATCH})
        WHERE h.date_of_task IS NULL
          AND EXISTS (#{MATCH})
        RETURNING h.id, h.date_of_task
      )
      INSERT INTO #{TABLE} (volunteer_hour_id, filled_value)
      SELECT id, date_of_task FROM filled
      ON CONFLICT (volunteer_hour_id) DO UPDATE SET filled_value = EXCLUDED.filled_value
      RETURNING volunteer_hour_id
    SQL
    left_blank = select_value("SELECT COUNT(*) FROM volunteer_hours WHERE date_of_task IS NULL").to_i
    say "volunteer_hours: #{filled.size} dates filled from completion requests, #{left_blank} still blank"
  end

  # Roll back 20261104150100 (the date_of_task check) first: this down sets the filled dates back to
  # NULL, which that check rejects even while NOT VALID. A normal rollback runs them in that order.
  # Only an hour that still holds the date written is blanked; raises, changing nothing, unless
  # every recorded hour is blanked, and the table is dropped only after that.
  def down
    return unless table_exists?(TABLE)

    recorded = select_value("SELECT COUNT(*) FROM #{TABLE}").to_i
    blanked = execute(<<~SQL.squish).cmd_tuples
      UPDATE volunteer_hours h SET date_of_task = NULL
      FROM #{TABLE} b
      WHERE h.id = b.volunteer_hour_id AND h.date_of_task = b.filled_value
    SQL
    if blanked != recorded
      raise "Cannot undo the volunteer hour dates: blanked #{blanked} of #{recorded} (the others were edited since or are gone); " \
            "nothing was changed and #{TABLE} was kept"
    end

    execute "DROP TABLE #{TABLE}"
  end
end
