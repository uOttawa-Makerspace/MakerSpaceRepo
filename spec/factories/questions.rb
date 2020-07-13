FactoryBot.define do
  factory :question do
    association :user, :admin
    description { Faker::Lorem.paragraph }

    trait :with_image do
      image { FilesTestHelper.png }
    end

    factory :question_with_training do
      transient do
        training_count { 1 }
      end
      after(:create) do |question, evaluator|
        create_list(:training, evaluator.training_count, :basic_training, question: question)
      end
    end
  end
end
