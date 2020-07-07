class CreateJoinTableQuestionsTrainings < ActiveRecord::Migration[5.2]
  def change
    create_join_table :questions, :trainings do |t|
      # t.index [:question_id, :training_id]
      # t.index [:training_id, :question_id]
    end
  end
end
