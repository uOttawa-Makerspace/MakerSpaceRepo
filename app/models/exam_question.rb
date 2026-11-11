class ExamQuestion < ApplicationRecord
  belongs_to :exam, optional: true
  belongs_to :question, optional: true
  has_one :exam_response, dependent: :nullify
  has_one :user, through: :exam

  # Adds up to n_questions random questions of the level to the exam and returns how many it added
  # (fewer than asked when the training has fewer at that level).
  def self.create_exam_questions(exam_id, training_id, n_questions, level)
    random_questions =
      Training
        .find(training_id)
        .questions
        .where(level: level)
        .random_records(n_questions)
    random_questions.each { |rq| ExamQuestion.create!(exam_id: exam_id, question_id: rq.id) }.size
  end
end
