class AddLearningModulesToVideos < ActiveRecord::Migration[6.0]
  def change
    add_reference :videos, :learning_module, index: true, foreign_key: true
  end
end
