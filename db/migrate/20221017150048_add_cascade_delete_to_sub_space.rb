class AddCascadeDeleteToSubSpace < ActiveRecord::Migration[6.1]
  def change
    remove_foreign_key :sub_space_bookings, :sub_spaces
    add_foreign_key :sub_space_bookings, :sub_spaces, on_delete: :cascade

    remove_foreign_key :sub_space_booking_statuses, :sub_space_bookings
    add_foreign_key :sub_space_booking_statuses,
                    :sub_space_bookings,
                    on_delete: :cascade
  end
end
