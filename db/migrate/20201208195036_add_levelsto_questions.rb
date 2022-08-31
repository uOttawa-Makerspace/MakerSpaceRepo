class AddLevelstoQuestions < ActiveRecord::Migration[6.0]
  def change
    add_column :questions, :level, :string, default: "Beginner"
  end
end
