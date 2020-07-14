FactoryBot.define do
  factory :exam_response do
    association :answer
    association :exam_question
  end
end