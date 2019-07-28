class ExamQuestion < ActiveRecord::Base
  belongs_to :exam
  belongs_to :question

  def self.create_exam_questions(exam_id, category, n_questions)
    random_questions = Question.where(category: category).random_records(n_questions)
    random_questions.each do |rq|
      ExamQuestion.create(exam_id: exam_id, question_id: rq.id)
    end
  end
end
