FactoryBot.define do
  factory :exam_question do
    association :question
    association :exam
  end
end