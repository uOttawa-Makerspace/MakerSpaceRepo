class AddEndDateToAnnoucements < ActiveRecord::Migration[6.0]
  def change
    add_column :announcements, :end_date, :date
  end
end
