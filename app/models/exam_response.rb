class ExamResponse < ApplicationRecord
  belongs_to :answer
  belongs_to :exam_question
  has_one :exam, through: :exam_question
  has_one :user, through: :exam
end
