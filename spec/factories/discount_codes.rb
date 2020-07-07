FactoryBot.define do
  factory :discount_code do

    trait 'working_discount_code' do
      user_id { 1 }
      price_rule_id { 1 }
      shopify_discount_code_id { Faker::Number.number(digits: 13) }
      code { Faker::Alphanumeric.alphanumeric(number: 30) }
      usage_count { 0 }
    end

    trait 'unused_code' do
      price_rule_id { 1 }
      shopify_discount_code_id { Faker::Number.number(digits: 13) }
      code { Faker::Alphanumeric.alphanumeric(number: 30) }
      usage_count { 0 }
    end

    trait 'used_discount_code' do
      price_rule_id { 1 }
      shopify_discount_code_id { Faker::Number.number(digits: 13) }
      code { Faker::Alphanumeric.alphanumeric(number: 30) }
      usage_count { 1 }
    end

    trait 'missing_shopify_discount_code_id' do
      user_id { 1 }
      price_rule_id { 1 }
      code { Faker::Alphanumeric.alphanumeric(number: 30) }
      usage_count { 0 }
    end

    trait 'missing_code' do
      user_id { 1 }
      price_rule_id { 1 }
      shopify_discount_code_id { Faker::Number.number(digits: 13) }
      usage_count { 0 }
    end

    trait 'other_discount_code' do
      code { Faker::Alphanumeric.alphanumeric(number: 30) }
      usage_count { 0 }
    end

  end
end
