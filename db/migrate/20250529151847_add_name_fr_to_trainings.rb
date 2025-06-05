class AddNameFrToTrainings < ActiveRecord::Migration[7.2]
  def change
    add_column :trainings, :name_fr, :string
  end
end
