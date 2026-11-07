# frozen_string_literal: true

namespace :bookings do
  desc "Copy each booking's status from its old status row into booking_status_id where the two differ " \
       "(the status row wins; the old table is never changed). Prints every booking changed with the value it had."
  task reconcile_statuses: :environment do
    # After the status column exists, every writer sets the column and the old status row together, so the
    # two can differ only because code from before the column wrote the status row alone: the row is newer.
    changed = SubSpaceBooking.connection.select_rows(<<~SQL.squish)
      WITH todo AS (
        SELECT b.id, b.booking_status_id AS was, s.booking_status_id AS now
        FROM sub_space_bookings b
        JOIN sub_space_booking_statuses s
          ON s.id = b.sub_space_booking_status_id AND s.sub_space_booking_id = b.id
        WHERE s.booking_status_id IS NOT NULL AND b.booking_status_id IS DISTINCT FROM s.booking_status_id
      ), updated AS (
        UPDATE sub_space_bookings b SET booking_status_id = todo.now FROM todo WHERE b.id = todo.id RETURNING b.id
      )
      SELECT todo.id, todo.was, todo.now FROM todo JOIN updated USING (id) ORDER BY todo.id
    SQL
    changed.each { |id, was, now| puts "booking #{id}: booking_status_id #{was.inspect} -> #{now}" }
    unmatched = SubSpaceBooking.where(booking_status_id: nil).pluck(:id)
    puts "#{changed.size} booking(s) changed"
    puts "#{unmatched.size} booking(s) still without a status (ids: #{unmatched.join(', ')})" if unmatched.any?
    Rails.logger.info("bookings:reconcile_statuses changed #{changed.map { |row| row.join(':') }.join(',')}")
  end
end
