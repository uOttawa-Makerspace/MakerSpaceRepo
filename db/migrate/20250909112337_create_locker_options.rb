class CreateLockerOptions < ActiveRecord::Migration[7.2]
  def change
    create_table :locker_options do |t|
      t.string :name
      t.string :value
      t.timestamps
    end
  end
end
