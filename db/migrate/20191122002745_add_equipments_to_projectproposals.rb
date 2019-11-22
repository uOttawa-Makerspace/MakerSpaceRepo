class AddEquipmentsToProjectproposals < ActiveRecord::Migration
  def change
    add_column :project_proposals, :equipments, :text, default: "Not informed."
  end
end
