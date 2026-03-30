class AddSubskillToLearningModule < ActiveRecord::Migration[7.2]
  def change
    add_column :learning_modules, :subskill, :string
  end
end
