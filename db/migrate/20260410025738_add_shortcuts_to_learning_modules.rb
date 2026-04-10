class AddShortcutsToLearningModules < ActiveRecord::Migration[7.2]
  def change
    add_column :learning_modules, :shortcut_name, :string
    add_index :learning_modules, :shortcut_name, unique: true
  end
end
