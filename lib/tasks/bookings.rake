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
        SELECT id, was_id, now_id, now() FROM todo RETURNING sub_space_booking_id
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

  desc "Put booking_status_id back to the value each reconcile_statuses change replaced, newest change first. " \
       "A booking whose column was changed since is left alone and listed. The record is kept."
  task restore_reconciled_statuses: :environment do
    connection = SubSpaceBooking.connection
    records = connection.select_rows(
      "SELECT id, sub_space_booking_id, was_booking_status_id, now_booking_status_id " \
      "FROM booking_status_reconciliations ORDER BY id DESC"
    )
    left = []
    restored = 0
    records.each do |_id, booking_id, was, now|
      done = connection.exec_update(
        "UPDATE sub_space_bookings SET booking_status_id = $1 WHERE id = $2 AND booking_status_id = $3",
        "restore", [was, booking_id, now]
      )
      restored += done
      left << booking_id if done.zero? && !connection.select_value(
        "SELECT 1 FROM sub_space_bookings WHERE id = #{booking_id.to_i} AND booking_status_id IS NOT DISTINCT FROM #{was.nil? ? 'NULL' : was.to_i}"
      )
    end
    puts "#{restored} booking(s) restored"
    puts "#{left.size} record(s) left alone because the column no longer holds the recorded value (booking ids: #{left.uniq.join(', ')})" if left.any?
  end
end
