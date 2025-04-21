class CreateDesignDays < ActiveRecord::Migration[7.2]
  def change
    create_table :design_days do |t|
      t.date :day # start day, no time
      t.string :sheet_key
      t.boolean :is_live
    end

    create_table :design_day_schedules do |t|
      t.references :design_day
      t.time :start
      t.time :end
      t.integer :ordering
      t.string :title_en
      t.string :title_fr
      t.integer :type
    end
  end
end
