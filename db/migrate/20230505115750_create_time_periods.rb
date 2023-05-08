class CreateTimePeriods < ActiveRecord::Migration[7.0]
  def change
    create_table :time_periods do |t|
      t.string :name
      t.date :start_date
      t.date :end_date
      t.timestamps
    end
  end
end
