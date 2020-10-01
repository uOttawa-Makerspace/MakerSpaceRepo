class AddActiveToPrograms < ActiveRecord::Migration[6.0]
  def change
    add_column :programs, :active, :boolean, default: true
  end
end
