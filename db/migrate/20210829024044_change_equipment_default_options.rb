class ChangeEquipmentDefaultOptions < ActiveRecord::Migration[6.0]
  def change
    change_column_default :project_proposals,
                          :equipments,
                          "Not informed / Pas informé"
  end
end
