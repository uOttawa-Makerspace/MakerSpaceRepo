# frozen_string_literal: true

# lockers:notify_expired_rentals (scheduled from this release) mails the renter of an active rental once its
# owned_until has passed, but only while that is within LockerRental::EXPIRY_NOTICE_WINDOW (14 days). Rentals that
# expired before that window were never mailed and must not be mailed now, so this marks them notified without
# sending anything: notified_of_cancellation_at is set to the migration time, and a fixed line is appended to
# staff_notes so the record does not read as if an email went out. contacted_for_clearance is left as it is.
#
# Rows: state = 'active', owned_until before now - 14 days, notified_of_cancellation_at NULL. A rental that
# expires at exactly now - 14 days is left to the task (its window includes the boundary), so nothing falls
# between the two. Re-running matches nothing.
#
# Reversible: down clears notified_of_cancellation_at and removes the marker line on exactly the rows carrying
# the marker. (A marked row is never mailed afterwards, so its timestamp can only be the one set here.)
class MarkLongExpiredLockerRentalsNotified < ActiveRecord::Migration[8.1]
  MARKER = "marked notified at deploy; no email sent"

  def up
    # The same 14 calendar days the task's window uses (LockerRental::EXPIRY_NOTICE_WINDOW), cut in Ruby so a
    # daylight-saving change cannot leave an hour between the two.
    cutoff = Time.current - 14.days
    execute <<~SQL
      UPDATE locker_rentals
      SET notified_of_cancellation_at = now(),
          staff_notes = CASE WHEN staff_notes IS NULL OR staff_notes = '' THEN #{quote(MARKER)}
                             ELSE staff_notes || E'\\n' || #{quote(MARKER)} END
      WHERE state = 'active'
        AND owned_until IS NOT NULL
        AND owned_until < #{quote(cutoff)}
        AND notified_of_cancellation_at IS NULL
    SQL
  end

  def down
    execute <<~SQL
      UPDATE locker_rentals
      SET notified_of_cancellation_at = NULL,
          staff_notes = NULLIF(replace(replace(staff_notes, E'\\n' || #{quote(MARKER)}, ''), #{quote(MARKER)}, ''), '')
      WHERE staff_notes LIKE #{quote("%#{MARKER}%")}
    SQL
  end
end
