FactoryBot.define do
  factory :exam_response do
    association :answer, :correct
    association :exam_question
    correct { true }

    trait :wrong do
      association :answer, :wrong
      correct { false }
    end
  end
end