FactoryBot.define do
  factory :training do
    name { Faker::Name.unique.name }
    description { Faker::Lorem.paragraph }
    association :skill

    trait :"3d_printing" do
      name { "3D Printing" }
    end

    trait :basic_training do
      name { "Basic Training" }
    end

    factory :training_with_questions do
      transient { question_count { 4 } }
      after(:create) do |training, evaluator|
        create_list(:question, evaluator.question_count, trainings: [training])
      end
    end

    factory :training_with_spaces do
      transient { space_count { 2 } }
      after(:create) do |training, evaluator|
        create_list(:space, evaluator.space_count, trainings: [training])
      end
    end

    factory :training_with_training_sessions do
      transient { training_session_count { 7 } }
      after(:create) do |training, evaluator|
        create_list(
          :training_session,
          evaluator.training_session_count,
          training: training
        )
      end
    end

    factory :training_with_require_trainings do
      transient { require_training_count { 6 } }
      after(:create) do |training, evaluator|
        create_list(
          :require_training,
          evaluator.require_training_count,
          training: training
        )
      end
    end

    factory :training_with_proficient_projects do
      transient { proficient_project_count { 3 } }
      after(:create) do |training, evaluator|
        create_list(
          :proficient_project,
          evaluator.proficient_project_count,
          training: training
        )
      end
    end
  end
end
