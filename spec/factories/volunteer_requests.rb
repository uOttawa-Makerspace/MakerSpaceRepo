FactoryBot.define do
  factory :volunteer_request do
    association :space
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
