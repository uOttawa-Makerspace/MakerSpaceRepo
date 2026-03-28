class AddStaffNotesToLockerRentals < ActiveRecord::Migration[7.2]
  def change
    add_column :locker_rentals, :staff_notes, :string
  end
end
