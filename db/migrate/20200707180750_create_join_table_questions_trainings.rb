class CreateJoinTableQuestionsTrainings < ActiveRecord::Migration[5.2]
  def change
    create_join_table :questions, :trainings do |t|
      # t.index [:question_id, :training_id]
      # t.index [:training_id, :question_id]
    end
    populate_tables
  end

  def populate_tables
    Training.all.find_each do |t|
      Question.where(training_id: t.id).find_each do |q|
        t.questions <<  q
      end
    end
  end
end
