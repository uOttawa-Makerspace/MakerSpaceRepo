class QuestionResponse < ActiveRecord::Base
  belongs_to :user
  belongs_to :exam
  belongs_to :question
  belongs_to :answer

  # belongs_to :answer
  # belongs_to :exam_question
  # has_one :question, through: :exam_question
  # has_one :exam, through: :exam_question
  # has_one :user, through: :exam
end
