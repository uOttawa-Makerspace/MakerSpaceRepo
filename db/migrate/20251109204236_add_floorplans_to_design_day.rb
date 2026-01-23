class AddFloorplansToDesignDay < ActiveRecord::Migration[7.2]
  def change
    add_column :design_days, :show_floorplans, :boolean, default: true
  end
end
