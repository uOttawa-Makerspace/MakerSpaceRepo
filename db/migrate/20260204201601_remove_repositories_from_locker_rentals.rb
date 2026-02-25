class RemoveRepositoriesFromLockerRentals < ActiveRecord::Migration[7.2]
  def change
    remove_column :locker_rentals, :repository_id, :reference
  end
end
