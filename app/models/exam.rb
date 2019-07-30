class Exam < ActiveRecord::Base
  belongs_to :user
  has_many :exam_questions,  dependent: :destroy
  has_many :question_responses
end
