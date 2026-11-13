class AddShowFloorplansDay2ToDesignDays < ActiveRecord::Migration[8.1]
  def change
    add_column :design_days, :show_floorplans_day2, :boolean, default: true
  end
end
