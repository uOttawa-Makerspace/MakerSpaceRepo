# frozen_string_literal: true

namespace :bookings do
  desc "Copy each booking's status from its old status row into booking_status_id where the two differ " \
       "(the status row wins; the old table is never changed). Records each change in " \
       "booking_status_reconciliations and prints it."
  task reconcile_statuses: :environment do
    # After the status column exists, every writer sets the column and the old status row together, so the
    # two can differ only because code from before the column wrote the status row alone: the row is newer.
    # The record rows are written by the same statement as the update.
    changed = SubSpaceBooking.connection.select_rows(<<~SQL.squish)
      WITH todo AS (
        SELECT b.id, b.booking_status_id AS was_id, s.booking_status_id AS now_id
        FROM sub_space_bookings b
        JOIN sub_space_booking_statuses s
          ON s.id = b.sub_space_booking_status_id AND s.sub_space_booking_id = b.id
        WHERE s.booking_status_id IS NOT NULL AND b.booking_status_id IS DISTINCT FROM s.booking_status_id
      ), recorded AS (
        INSERT INTO booking_status_reconciliations (sub_space_booking_id, was_booking_status_id, now_booking_status_id, created_at)
        SELECT id, was_id, now_id, now() FROM todo ORDER BY id RETURNING sub_space_booking_id
      ), updated AS (
        UPDATE sub_space_bookings b SET booking_status_id = todo.now_id FROM todo WHERE b.id = todo.id RETURNING b.id
      )
      SELECT todo.id, todo.was_id, todo.now_id FROM todo
      JOIN updated USING (id) JOIN recorded ON recorded.sub_space_booking_id = todo.id ORDER BY todo.id
    SQL
    changed.each { |id, was, now| puts "booking #{id}: booking_status_id #{was.inspect} -> #{now}" }
    unmatched = SubSpaceBooking.where(booking_status_id: nil).pluck(:id)
    puts "#{changed.size} booking(s) changed"
    puts "#{unmatched.size} booking(s) still without a status (ids: #{unmatched.join(', ')})" if unmatched.any?
  end

  desc "Put booking_status_id back to the value each reconcile_statuses change replaced, newest change first, " \
       "and mark each record restored in the same statement. A booking whose column was changed since (compared " \
       "by value) or that no longer exists is left alone and listed. Running it again restores nothing more."
  task restore_reconciled_statuses: :environment do
    connection = SubSpaceBooking.connection
    records = connection.select_rows(
      "SELECT r.id, r.sub_space_booking_id, r.was_booking_status_id, r.now_booking_status_id, " \
      "EXISTS (SELECT 1 FROM sub_space_bookings b WHERE b.id = r.sub_space_booking_id) " \
      "FROM booking_status_reconciliations r WHERE r.restored_at IS NULL ORDER BY r.id DESC"
    )
    gone = []
    changed_since = []
    blocked = []
    restored = 0
    left_alone = []
    records.each do |id, booking_id, was, now, exists|
      # an older change of a booking is not undone once a newer one was left alone: the booking changed after it
      if left_alone.include?(booking_id)
        blocked << booking_id
        next
      end
      done = connection.exec_update(<<~SQL.squish, "restore", [was, booking_id, now, id])
        WITH restored AS (
          UPDATE sub_space_bookings SET booking_status_id = $1 WHERE id = $2 AND booking_status_id = $3 RETURNING id
        )
        UPDATE booking_status_reconciliations SET restored_at = now()
        WHERE id = $4 AND EXISTS (SELECT 1 FROM restored)
      SQL
      if done.positive?
        restored += done
        puts "booking #{booking_id}: booking_status_id #{now} -> #{was.inspect}"
      else
        (exists ? changed_since : gone) << booking_id
        left_alone << booking_id
      end
    end
    puts "#{restored} booking(s) restored"
    puts "#{changed_since.size} record(s) left alone, the column no longer holds the recorded value (booking ids: #{changed_since.uniq.join(', ')})" if changed_since.any?
    puts "#{blocked.size} record(s) left alone, a newer change of the booking was left alone (booking ids: #{blocked.uniq.join(', ')})" if blocked.any?
    puts "#{gone.size} record(s) left alone, booking gone (booking ids: #{gone.uniq.join(', ')})" if gone.any?
  end
end
