class CreateRecurringBookings < ActiveRecord::Migration[7.0]
  def change
    create_table :recurring_bookings do |t|
      # id is implicit
      t.timestamps
    end

    change_table :sub_space_bookings do |t|
      # reference the recurring_booking handle
      t.belongs_to :recurring_booking, foreign_key: true, optional: true
    end
  end
end
