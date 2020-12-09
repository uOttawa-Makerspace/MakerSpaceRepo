FactoryBot.define do
  factory :learning_module_track do
    association :user
    association :learning_module

    status { "In progress" }

    trait :completed do
      status { "Completed" }
    end
  end
end
