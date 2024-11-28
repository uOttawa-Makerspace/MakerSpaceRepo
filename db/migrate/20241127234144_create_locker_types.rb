class CreateLockerTypes < ActiveRecord::Migration[7.0]
  def change
    create_table :locker_types do |t|
      t.string :short_form # Short code
      t.string :description # where is it located, extra info
      t.boolean :available, default: true # should be displayed at all?
      t.string :available_for # staff, admin, students, general public
      t.integer :quantity, default: 0 # how many are available
      t.decimal :cost, default: 0 # how much does it cost
      t.timestamps
    end

    create_table :locker_rentals do |t|
      t.references :locker_type
      t.references :rented_by # user
      t.string :state # not approved, ask for payment, paid
      t.datetime :owned_until # NOTE should this be a string or a datetime?
      t.timestamps
    end
  end
end
