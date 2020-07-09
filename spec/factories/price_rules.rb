FactoryBot.define do
  factory :price_rule do
    shopify_price_rule_id { Faker::Number.number(digits: 13) }
    title { "5$ coupon" }
    value { 5 }
    cc { 50 }

    factory :price_rule_with_discount_codes do
      transient do
        discount_code_count { 5 }
      end
      after(:create) do |price_rule, evaluator|
        create_list(:discount_code, evaluator.discount_code_count, price_rule: price_rule)
      end
    end
  end
end
