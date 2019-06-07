class AddActiveToSkill < ActiveRecord::Migration
  def change
    add_column :skills, :active, :boolean, default: true
  end
end
