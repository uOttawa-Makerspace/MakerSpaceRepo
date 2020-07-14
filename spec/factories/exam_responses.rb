FactoryBot.define do
  factory :exam_response do
    association :question
    association :exam
  end
end