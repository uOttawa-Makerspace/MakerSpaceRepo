class CreatePopularHours < ActiveRecord::Migration[6.0]
  def change
    create_table :popular_hours do |t|
      t.references :space, index: true, foreign_key: true
      t.float :mean,      default: 0
      t.integer :hour
      t.integer :day
      t.integer :count,   default: 0

      t.timestamps
    end
  end
end
