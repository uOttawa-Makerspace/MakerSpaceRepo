class CreateDropOffLocations < ActiveRecord::Migration[6.0]
  def change
    create_table :drop_off_locations do |t|
      t.string :name
      t.timestamps
    end
  end
end
