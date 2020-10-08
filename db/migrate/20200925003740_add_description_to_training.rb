class AddDescriptionToTraining < ActiveRecord::Migration[6.0]
  def change
    add_column :trainings, :description, :string
  end
end
