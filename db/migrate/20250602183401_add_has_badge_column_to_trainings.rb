class AddHasBadgeColumnToTrainings < ActiveRecord::Migration[7.2]
  def change
    add_column :trainings, :has_badge, :boolean, default: true
  end
end
