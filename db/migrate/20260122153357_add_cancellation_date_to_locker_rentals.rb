class AddCancellationDateToLockerRentals < ActiveRecord::Migration[7.2]
  def change
    add_column :locker_rentals, :cancelled_at, :datetime
    add_column :locker_rentals, :notified_of_cancellation, :boolean
  end
end
