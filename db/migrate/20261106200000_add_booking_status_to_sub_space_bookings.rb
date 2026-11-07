# A booking's status moves onto the booking row (booking_status_id), so the booking and its status
# row no longer point at each other. This step is additive: it adds a nullable column with a foreign
# key and an index, and copies each booking's status into it from the status row it is linked to.
# sub_space_booking_statuses and the old link column are not touched.
#
# Before copying, every booking must have exactly one status row, linked from the booking and
# holding a status. If any does not, the migration stops (nothing is changed) and lists the booking ids.
# It also creates booking_status_reconciliations, where the bookings:reconcile_statuses task records every
# column value it changes, so it can be put back. down drops that table and the new column; nothing else.
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
    create_table :booking_status_reconciliations do |t|
      t.references :sub_space_booking, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :was_booking_status_id
      t.bigint :now_booking_status_id, null: false
      t.datetime :created_at, null: false
    end
    execute <<~SQL.squish
      UPDATE sub_space_bookings b
      SET booking_status_id = s.booking_status_id
      FROM sub_space_booking_statuses s
      WHERE s.id = b.sub_space_booking_status_id
    SQL
  end

  def down
    drop_table :booking_status_reconciliations
    remove_reference :sub_space_bookings, :booking_status, foreign_key: true, index: true
  end
end
