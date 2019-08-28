class AddTrainingIdToQuestions < ActiveRecord::Migration
  def change
    add_column :questions, :training_id, :integer
  end
end
