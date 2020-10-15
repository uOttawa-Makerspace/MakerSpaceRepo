class AddingMoreThingsToLearningModules < ActiveRecord::Migration[6.0]
  def change
    add_column :learning_modules, :level, :string, default: 'Beginner'
    add_column :learning_modules, :has_project_kit, :boolean
  end
end
