class CreatePopularHours < ActiveRecord::Migration[6.0]
  def change
    create_table :popular_hours do |t|
      t.integer :mean
      t.integer :space_id
      t.integer :hour
      t.integer :day
      t.integer :count

      t.timestamps
    end
  end
end
