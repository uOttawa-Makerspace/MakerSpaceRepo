class RemoveForeignKeyFromPreferredLockers < ActiveRecord::Migration[7.2]
  def change
    remove_foreign_key :locker_rentals, column: :preferred_locker_id
  end
end
