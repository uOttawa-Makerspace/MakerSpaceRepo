class AddValuesToProficientProject < ActiveRecord::Migration
  def change
    add_column :proficient_projects, :cc, :integer
    add_column :proficient_projects, :proficient, :boolean, default: true
  end
end
