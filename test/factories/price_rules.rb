# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :price_rule do
    shopify_price_rule_id "1"
    title "MyString"
    value 1
    cc 1
    usage_limit 1
  end
end
