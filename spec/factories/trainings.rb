FactoryBot.define do
  factory :training do
    name { Faker::Name.unique.name }

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

    factory :training_with_spaces do
      transient do
        space_count { 2 }
      end
      after(:create) do |training, evaluator|
        create_list(:space, evaluator.space_count, trainings: [training])
      end
    end
  end
end


