class SimpifyOpeningHours < ActiveRecord::Migration[7.0]
  def change
    change_table :opening_hours do |t|
      # Target audience
      t.column :target, :string
      # Days of the week, seven in total
      # nil if closed
      t.column :sunday, :time, default: nil, null: true
      t.column :monday, :time, default: nil, null: true
      t.column :tuesday, :time, default: nil, null: true
      t.column :wednesday, :time, default: nil, null: true
      t.column :thursday, :time, default: nil, null: true
      t.column :friday, :time, default: nil, null: true
      t.column :saturday, :time, default: nil, null: true
      # Notes at the bottom. Is text not string!
      t.column :notes, :text

      # Remove old columns
      t.remove :students, type: :string
      t.remove :public, type: :string
      t.remove :summer, type: :string
    end
  end
end
