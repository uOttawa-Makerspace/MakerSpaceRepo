class CreateShadowingHours < ActiveRecord::Migration[6.0]
  def change
    create_table :shadowing_hours do |t|
      t.references :user, index: true, foreign_key: true
      t.string :event_id
      t.datetime :start_time
      t.datetime :end_time
      t.timestamps
    end
  end
end
