class CreateOpeningHours < ActiveRecord::Migration[6.0]
  def change
    create_table :opening_hours do |t|
      t.string "students"
      t.string "public"
      t.string "summer"
      t.belongs_to :contact_info

      t.timestamps
    end
  end
end
