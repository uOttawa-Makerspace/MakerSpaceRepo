class AddCheckoutDateToLockerRentals < ActiveRecord::Migration[7.2]
  def change
    add_column :locker_rentals, :sent_to_checkout_at, :datetime
    change_column :locker_rentals, :paid_at, :datetime
    add_column :locker_rentals, :notified_of_cancellation_at, :datetime
    remove_column :locker_rentals, :notified_of_cancellation, :boolean
  end
end
