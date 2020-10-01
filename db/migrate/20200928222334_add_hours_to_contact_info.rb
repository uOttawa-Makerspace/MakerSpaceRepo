class AddHoursToContactInfo < ActiveRecord::Migration[6.0]
  def change
    add_column :contact_infos, :show_hours, :boolean
  end
end
