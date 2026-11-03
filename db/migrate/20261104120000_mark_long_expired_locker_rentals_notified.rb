# frozen_string_literal: true

# lockers:notify_expired_rentals (scheduled from this release) mails the renter of an active rental once its
# owned_until has passed, but only while that is recent (LockerRental::EXPIRY_NOTICE_WINDOW, plus one grace day).
# Rentals that expired before the window were never mailed and must not be mailed now, so this marks them
# notified without sending anything: notified_of_cancellation_at is set to the migration time, and a line carrying
# this migration's version is appended to staff_notes so the record does not read as if an email went out.
# contacted_for_clearance is left as it is.
#
# Rows: state = 'active', owned_until before now - EXPIRY_NOTICE_WINDOW, notified_of_cancellation_at NULL. The
# task looks back one day further than that, so a rental that ages past the window between this migration and the
# first daily run is still mailed: nothing falls between the two. Re-running matches nothing.
#
# staff_notes: NULL becomes the marker line; any other text (including an empty string) gets a newline and the
# marker line after it.
#
# Reversible: down matches exactly the rows whose staff_notes ends with the marker line, clears their
# notified_of_cancellation_at, and removes the marker line and the newline before it. Notes that were NULL when up
# ran (now exactly the marker) become NULL again; an empty string comes back as an empty string.
class MarkLongExpiredLockerRentalsNotified < ActiveRecord::Migration[8.1]
  MARKER = "[20261104120000] marked notified at deploy; no email sent"

  def up
    cutoff = Time.current - LockerRental::EXPIRY_NOTICE_WINDOW
    execute <<~SQL
      UPDATE locker_rentals
      SET notified_of_cancellation_at = now(),
          staff_notes = CASE WHEN staff_notes IS NULL THEN #{quote(MARKER)}
                             ELSE staff_notes || E'\\n' || #{quote(MARKER)} END
      WHERE state = 'active'
        AND owned_until IS NOT NULL
        AND owned_until < #{quote(cutoff)}
        AND notified_of_cancellation_at IS NULL
    SQL
  end

  def down
    line = "\n#{MARKER}"
    execute <<~SQL
      UPDATE locker_rentals
      SET notified_of_cancellation_at = NULL,
          staff_notes = CASE WHEN staff_notes = #{quote(MARKER)} THEN NULL
                             ELSE left(staff_notes, length(staff_notes) - length(#{quote(line)})) END
      WHERE staff_notes = #{quote(MARKER)}
         OR right(staff_notes, length(#{quote(line)})) = #{quote(line)}
    SQL
  end
end
