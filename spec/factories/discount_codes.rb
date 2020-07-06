FactoryBot.define do
  factory :discount_code do
    trait 'working_discount_code' do
      id { 1 }
      user_id { 1 }
      shopify_discount_code_id { Faker::Number.number(digits: 13) }
      code { "71e7c5903acd1ab536c22d396622s4" }
      usage_count { 0 }
    end

    trait 'other_discount_code' do
      code { Faker::Alphanumeric.alphanumeric(number: 30) }
      usage_count { 0 }
    end
  end
end
