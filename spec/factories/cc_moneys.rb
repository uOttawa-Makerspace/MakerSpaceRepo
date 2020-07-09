FactoryBot.define do
  factory :cc_money do
    cc { Faker::Number.number(digits: 2) }
    trait :with_discount_code do
      association :discount_code
    end

    trait :hundred do
      cc { 100 }
    end
  end
end
