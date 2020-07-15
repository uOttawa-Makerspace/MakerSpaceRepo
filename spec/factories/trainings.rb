FactoryBot.define do
  factory :training do
    name { Faker::Name.unique.name }

    trait :test do
      name { "Test" }
    end

    trait :test2 do
      name { "Test2" }
    end

    trait :'3d_printing' do
      name { "3D Printing" }
    end

    trait :basic_training do
      name { "Basic Training" }
    end

    factory :training_with_questions do
      transient do
        question_count { 4 }
      end
      after(:create) do |training, evaluator|
        create_list(:question, evaluator.question_count, trainings: [training])
      end
    end
  end
end


