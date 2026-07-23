class AddScormToLearningModules < ActiveRecord::Migration[7.2]
  def change
    add_column :learning_modules, :scorm_prefix, :string
    add_column :learning_modules, :scorm_entry_point, :string
    add_column :learning_modules, :scorm_status, :integer, default: 0
  end
end
