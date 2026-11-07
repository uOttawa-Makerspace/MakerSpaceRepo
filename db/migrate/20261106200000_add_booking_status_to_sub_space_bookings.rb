# A booking's status moves onto the booking row (booking_status_id), so the booking and its status
# row no longer point at each other. This step is additive: it adds a nullable column with a foreign
# key and an index, and copies each booking's status into it from the status row it is linked to.
# sub_space_booking_statuses and the old link column are not touched.
#
# Before copying, every booking must have exactly one status row, linked from the booking and
# holding a status. If any does not, the migration stops (nothing is changed) and lists the booking ids.
# down removes only the new column.
class AddBookingStatusToSubSpaceBookings < ActiveRecord::Migration[8.1]
  PROBLEMS = <<~SQL.squish
    SELECT b.id FROM sub_space_bookings b
    WHERE (SELECT COUNT(*) FROM sub_space_booking_statuses s WHERE s.sub_space_booking_id = b.id) <> 1
       OR NOT EXISTS (
         SELECT 1 FROM sub_space_booking_statuses s
         WHERE s.id = b.sub_space_booking_status_id
           AND s.sub_space_booking_id = b.id
           AND s.booking_status_id IS NOT NULL)
    ORDER BY b.id
  SQL

  def up
    ids = select_values(PROBLEMS)
    if ids.any?
      raise "Cannot copy booking statuses: #{ids.size} booking(s) do not have exactly one status row " \
            "linked both ways (ids: #{ids.join(', ')}); nothing was changed"
    end

    add_reference :sub_space_bookings, :booking_status, foreign_key: true, index: true
    execute <<~SQL.squish
      UPDATE sub_space_bookings b
      SET booking_status_id = s.booking_status_id
      FROM sub_space_booking_statuses s
      WHERE s.id = b.sub_space_booking_status_id
    SQL
  end

  def down
    remove_reference :sub_space_bookings, :booking_status, foreign_key: true, index: true
  end
end
