class Answer < ApplicationRecord
  belongs_to :question
  has_many :exam_responses
  scope :randomize_answers, -> { order('random()') }
end
