FactoryBot.define do
  factory :key_transaction do
    deposit_amount { Faker::Number.number(digits: 2) }

    trait :returned do
      return_date { Date.today }
    end

    trait :deposit_returned do
      deposit_return_date { Date.today }
    end
  end
end
