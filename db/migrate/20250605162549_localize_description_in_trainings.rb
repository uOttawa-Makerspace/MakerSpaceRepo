class LocalizeDescriptionInTrainings < ActiveRecord::Migration[7.2]
  def up
    add_column :trainings, :description_fr, :string
    change_table :trainings do |t|
      t.rename :description, :description_en
    end
  end

  def down
    remove_column :trainings, :description_fr, :string
    change_table :trainings do |t|
      t.rename :description_en, :description
    end
  end
end
