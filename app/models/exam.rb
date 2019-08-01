class Exam < ActiveRecord::Base
  belongs_to :user
  has_many :exam_questions,  dependent: :destroy
  has_many :question_responses
  has_many :questions, through: :exam_questions

  STATUS = { :not_started => "not started",
              :started => "started",
              :incomplete => "incomplete",
              :passed => "passed",
              :failed => "failed"}
end