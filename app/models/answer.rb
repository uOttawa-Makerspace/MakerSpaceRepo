class Answer < ApplicationRecord
  belongs_to :question, optional: true
  has_many :exam_responses
  scope :randomize_answers, -> { order(Arel.sql("random()")) }
  has_rich_text :description
end
