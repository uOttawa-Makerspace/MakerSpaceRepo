class AddRepositoryToLockerRentals < ActiveRecord::Migration[7.2]
  def change
    add_reference :locker_rentals, :repository, null: true # allow nulls
    add_column :locker_rentals, :requested_as, :string
    reversible do |direction|
      # Some lockers are already made, use SQL to set a default value
      direction.up { execute "UPDATE locker_rentals SET requested_as = 'staff';" }
    end
  end
end
