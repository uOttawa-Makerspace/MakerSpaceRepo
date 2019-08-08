class Exam < ActiveRecord::Base
  belongs_to :user
  has_many :exam_questions,  dependent: :destroy
  has_many :questions, through: :exam_questions
  has_many :exam_responses, through: :exam_questions
  belongs_to :training_session

  STATUS = { :not_started => "not started",
              :incomplete => "incomplete",
              :passed => "passed",
              :failed => "failed"}

  SCORE_TO_PASS = 75

  def calculate_score
    all_questions = self.exam_questions.count
    exam_responses_right = self.exam_responses.where(correct: true).count
    return (exam_responses_right*100.0/all_questions).round
  end
end