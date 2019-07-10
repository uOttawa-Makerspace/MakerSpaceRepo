class Answer < ActiveRecord::Base
  belongs_to :question
  scope :randomize_answers, ->{order('random()')}
end
