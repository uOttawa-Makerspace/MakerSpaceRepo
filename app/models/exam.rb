class Exam < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :training_session, optional: true
  has_many :exam_questions, dependent: :destroy
  has_many :questions, through: :exam_questions
  has_many :exam_responses, through: :exam_questions
  has_one :training, through: :training_session

  STATUS = {
    not_started: "not started",
    incomplete: "incomplete",
    passed: "passed",
    failed: "failed"
  }.freeze

  SCORE_TO_PASS = 68

  def calculate_score
    all_questions = exam_questions.count
    exam_responses_right = exam_responses.where(correct: true).count
    (exam_responses_right * 100.0 / all_questions).round
  end

  # An exam accepts answers and can be finished only until it is graded or expires.
  def open_for_answers?
    ungraded? && !expired?
  end

  def ungraded?
    status.in?([STATUS[:not_started], STATUS[:incomplete]])
  end

  def expired?
    expired_at.present? && expired_at.past?
  end

  def failed?
    status == "failed"
  end
end
