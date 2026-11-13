# frozen_string_literal: true

# lockers:notify_expired_rentals (scheduled from this release) mails the renter of an active rental once its
# owned_until has passed, but only while that is recent (14 days, plus one grace day).
# Rentals that expired before the window were never mailed and must not be mailed now, so this marks them
# notified without sending anything: notified_of_cancellation_at is set to one timestamp for all of them, and a
# line carrying this migration's version and that timestamp is appended to staff_notes so the record does not read as if an email went out.
# contacted_for_clearance is left as it is.
#
# Rows: state = 'active', owned_until before now - 14 days (the notice window at the time of writing; the task looks
# back one day further), notified_of_cancellation_at NULL. A rental that ages past the window between this migration
# and the first daily run is therefore still mailed: nothing falls between the two. Re-running matches nothing.
#
# staff_notes: NULL becomes the marker line; any other text (including an empty string) gets a newline and the
# marker line after it.
#
# Reversible: down matches exactly the rows whose staff_notes ends with a marker line. It clears
# notified_of_cancellation_at only where that still equals the timestamp written in the line (a rental renewed and
# notified again since keeps its real notice), and removes the marker line and the newline before it. Notes that
# were NULL when up ran (now exactly the marker) become NULL again; an empty string comes back as an empty string.
class MarkLongExpiredLockerRentalsNotified < ActiveRecord::Migration[8.1]
  VERSION = "20261104120000"
  MARKER_TEXT = "marked notified at deploy; no email sent"
  # The marker line as a Postgres regular expression: version, then the timestamp up wrote.
  MARKER_PATTERN = "\\[#{VERSION} ([0-9TZ:-]+)\\] #{MARKER_TEXT}"

  def up
    marked_at = Time.now.utc.change(usec: 0)
    marker = "[#{VERSION} #{marked_at.iso8601}] #{MARKER_TEXT}"
    # 14 calendar days in the app's time zone, as the task's window is counted
    cutoff = (Time.zone.at(marked_at) - 14.days).utc
    execute <<~SQL
      UPDATE locker_rentals
      SET notified_of_cancellation_at = #{quote(marked_at)},
          staff_notes = CASE WHEN staff_notes IS NULL THEN #{quote(marker)}
                             ELSE staff_notes || E'\\n' || #{quote(marker)} END
      WHERE state = 'active'
        AND owned_until IS NOT NULL
        AND owned_until < #{quote(cutoff)}
        AND notified_of_cancellation_at IS NULL
    SQL
  end

  def down
    line = quote(MARKER_PATTERN)
    execute <<~SQL
      UPDATE locker_rentals
      SET notified_of_cancellation_at =
            CASE WHEN notified_of_cancellation_at = (substring(staff_notes from #{line} || '$'))::timestamp
                 THEN NULL ELSE notified_of_cancellation_at END,
          staff_notes =
            CASE WHEN staff_notes ~ ('^' || #{line} || '$') THEN NULL
                 ELSE regexp_replace(staff_notes, E'\\n' || #{line} || '$', '') END
      WHERE staff_notes ~ ('(^|\n)' || #{line} || '$')
    SQL
  end
end
