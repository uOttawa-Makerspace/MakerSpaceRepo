class AddApprovalInfoToSubSpaceBookings < ActiveRecord::Migration[7.0]
  def change
    add_reference :sub_space_bookings,
                  :approved_by,
                  foreign_key: {
                    to_table: :users
                  },
                  optional: true
    add_column :sub_space_bookings, :approved_at, :datetime, optional: true
  end
end
