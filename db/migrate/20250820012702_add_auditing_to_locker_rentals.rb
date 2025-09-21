class AddAuditingToLockerRentals < ActiveRecord::Migration[7.2]
  def change
    change_table :locker_rentals do |t|
      t.date :paid_at
      # Who cancelled or approved a locker rental
      t.references :decided_by, null: true, foreign_key: { to_table: :users }

      t.foreign_key :users, column: :rented_by_id
    end
  end
end
