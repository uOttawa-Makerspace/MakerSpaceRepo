class CreateTrainingSessions < ActiveRecord::Migration
  def change
    create_table :training_sessions do |t|
      t.string :name
      t.references :staff, index: true, foreign_key: true
      t.date :date
      t.time :time

      t.timestamps null: false
    end
  end
end
