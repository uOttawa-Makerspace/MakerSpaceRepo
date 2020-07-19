FactoryBot.define do
  factory :volunteer_task_request do

    association :volunteer_task
    association :user, :volunteer

    trait :approved do
      approval { true }
    end

    trait :rejected do
      approval { false }
    end

    trait :not_processed do
      approval { nil }
    end

  end

end
