class AddPreferredLockerToLockerRentals < ActiveRecord::Migration[7.2]
  def change
    add_reference :locker_rentals, :preferred_locker, foreign_key: { to_table: :lockers }
  end
end
