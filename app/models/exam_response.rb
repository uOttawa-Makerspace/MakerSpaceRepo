class ExamResponse < ApplicationRecord
  belongs_to :answer, optional: true
  belongs_to :exam_question, optional: true
  has_one :exam, through: :exam_question
  has_one :user, through: :exam
end
