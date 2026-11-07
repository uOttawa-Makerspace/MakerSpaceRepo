class Answer < ApplicationRecord
  belongs_to :question, optional: true
  has_many :exam_responses, dependent: :nullify
  has_rich_text :description
end
