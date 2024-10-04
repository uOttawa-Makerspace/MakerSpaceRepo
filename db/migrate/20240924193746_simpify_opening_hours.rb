class SimpifyOpeningHours < ActiveRecord::Migration[7.0]
  def change
    change_table :opening_hours do |t|
      # Target audience
      t.column :target_en, :string
      t.column :target_fr, :string
      # Days of the week, seven in total
      # nil if closed
      %i[sunday monday tuesday wednesday thursday friday saturday].each do |day|
        t.column "#{day}_opening", :time, default: nil, null: true
        t.column "#{day}_closing", :time, default: nil, null: true
        t.column "#{day}_closed_all_day", :boolean, default: false
      end
      t.column :closed_all_week, :boolean, default: false
      # Notes at the bottom. Is text not string!
      t.column :notes_en, :text
      t.column :notes_fr, :text

      # Remove old columns
      t.remove :students, type: :string
      t.remove :public, type: :string
      t.remove :summer, type: :string
    end
  end
end
