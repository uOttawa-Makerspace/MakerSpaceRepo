class CreateLockers < ActiveRecord::Migration[7.2]
  def change
    create_table :lockers do |t|
      t.string :specifier, index: true
      t.boolean :available, default: true, null: false

      t.timestamps
    end

    change_table :locker_rentals do |t|
      # Simplify lockers, they're all the same type now
      t.remove_references :locker_type
      t.references :locker, index: true, null: true, foreign_key: true
      t.remove :locker_specifier, type: :string
    end

    drop_table :locker_types do |t|
      t.string :short_form
      t.string :description
      t.boolean :available
      t.string :available_for
      t.integer :quantity
      t.decimal :cost
      t.timestamps
    end
  end
end
