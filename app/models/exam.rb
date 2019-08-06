class Exam < ActiveRecord::Base
  belongs_to :user
  has_many :exam_questions,  dependent: :destroy
  has_many :questions, through: :exam_questions
  has_many :exam_responses, through: :exam_questions

  STATUS = { :not_started => "not started",
              :incomplete => "incomplete",
              :passed => "passed",
              :failed => "failed"}

  SCORE_TO_PASS = 75

  def self.calculate_score
    exam_responses = self.exam_responses
    all = exam_responses.count
    right = exam_responses.where(correct: true)
    return (right*100.0/all).round
  end
end