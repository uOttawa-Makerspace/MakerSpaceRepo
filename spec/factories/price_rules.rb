FactoryBot.define do
  factory :price_rule do
    shopify_price_rule_id { Faker::Number.number(digits: 13) }
    title { "5$ coupon" }
    value { 5 }
    cc { 50 }

    trait 'working_print_rule' do
      shopify_price_rule_id { Faker::Number.number(digits: 13) }
      title { "5$ coupon" }
      value { 5 }
      cc { 50 }
    end

    trait 'working_print_rule_with_id' do
      id { 1 }
      shopify_price_rule_id { Faker::Number.number(digits: 13) }
      title { "5$ coupon" }
      value { 5 }
      cc { 50 }
    end

    trait 'working_print_rule_with_id' do
      id { 100 }
      shopify_price_rule_id { Faker::Number.number(digits: 13) }
      title { "5$ coupon" }
      value { 5 }
      cc { 50 }
    end

    trait 'missing_shopify_price_rule_id' do
      title { "5$ coupon" }
      value { 5 }
      cc { 50 }
    end

    trait 'missing_title' do
      shopify_price_rule_id { Faker::Number.number(digits: 13) }
      value { 5 }
      cc { 50 }
    end

    trait 'missing_value' do
      shopify_price_rule_id { Faker::Number.number(digits: 13) }
      title { "5$ coupon" }
      cc { 50 }
    end

    trait 'missing_cc' do
      shopify_price_rule_id { Faker::Number.number(digits: 13) }
      title { "5$ coupon" }
      value { 5 }
    end

  end
end
