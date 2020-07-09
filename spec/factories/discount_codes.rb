FactoryBot.define do
  factory :discount_code do
    association :user, :regular_user
    association :price_rule
    shopify_discount_code_id { Faker::Number.number(digits: 13) }
    code { Faker::Alphanumeric.alphanumeric(number: 30) }

    trait 'unused' do
      usage_count { 0 }
    end

    trait 'used' do
      usage_count { 1 }
    end

    factory :discount_code_with_cc_moneys do
      transient do
        cc_money_count { 5 }
      end
      after(:create) do |discount_code, evaluator|
        create_list(:cc_money, evaluator.cc_money_count, discount_code: discount_code)
      end
    end
  end
end
