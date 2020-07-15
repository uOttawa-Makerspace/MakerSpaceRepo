FactoryBot.define do
  factory :exam_question do
    association :question
    association :exam

    trait :with_question_and_answers do
      association :question, factory: :question_with_answers
    end

    factory :exam_question_with_exam_response do
      after(:create) do |exam_question|
        create_list(:exam_response, 1, exam_question: exam_question)
      end
    end
  end
end