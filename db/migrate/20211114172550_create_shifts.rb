class CreateShifts < ActiveRecord::Migration[6.0]
  def change
    create_table :shifts do |t|
      t.text :reason
      t.references :space, foreign_key: true
      t.references :user, foreign_key: true
      t.datetime :start_datetime
      t.datetime :end_datetime
      t.timestamps
    end
  end
end
