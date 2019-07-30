class QuestionResponse < ActiveRecord::Base
  belongs_to :user
  belongs_to :exam
  belongs_to :question
  belongs_to :answer
end
