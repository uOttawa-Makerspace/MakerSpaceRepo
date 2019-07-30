class Answer < ActiveRecord::Base
  belongs_to :question
  has_many :question_responses
  scope :randomize_answers, ->{order('random()')}
end
