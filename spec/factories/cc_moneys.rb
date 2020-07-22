FactoryBot.define do
  factory :cc_money do
    association :user, :regular_user
    cc { Faker::Number.number(digits: 2) }

    trait :with_discount_code do
      association :discount_code
    end

    trait :with_volunteer_task do
      association :volunteer_task
    end

    trait :with_proficient_project do
      association :order
      association :proficient_project
    end

    trait :hundred do
      cc { 100 }
    end
  end
end
