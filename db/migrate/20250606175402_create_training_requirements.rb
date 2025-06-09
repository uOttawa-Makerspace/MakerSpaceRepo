class CreateTrainingRequirements < ActiveRecord::Migration[7.2]
  def change
    create_table :training_requirements do |t|
      t.timestamps null: false
      t.references :training, index: true, foreign_key: true
      t.references :proficient_project, index: true, foreign_key: true
    end
  end
end
