class CreateSubSpaceBookingStatuses < ActiveRecord::Migration[6.1]
  def change
    create_table :sub_space_booking_statuses do |t|
      t.references :sub_space_booking, index: true, foreign_key: true
      t.timestamps
    end
  end
end
