# frozen_string_literal: true

FactoryBot.define do
  factory :coupon_code do
    code { Faker::Alphanumeric.alphanumeric(number: 30) }
    dollar_cost { 10.0 }
    cc_cost { 10 }

    trait :unclaimed do
      user { nil }
    end

    trait :claimed do
      association :user
    end
  end
end
