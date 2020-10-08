class CreateLearningModuleTracks < ActiveRecord::Migration[6.0]
  def change
    create_table :learning_module_tracks do |t|
      t.string :status, default: "In progress"
      t.references :learning_module, index: true, foreign_key: true
      t.references :user, index: true, foreign_key: true

      t.timestamps
    end
  end
end
