class CreateLearningModules < ActiveRecord::Migration[6.0]
  def change
    create_table :learning_modules do |t|
      t.integer :training_id
      t.string :title
      t.text :description

      t.timestamps null: false
    end
  end
end
