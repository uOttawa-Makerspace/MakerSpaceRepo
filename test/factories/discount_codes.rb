# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :discount_code do
    price_rule nil
    user nil
    shopify_discount_code_id "MyString"
    code "MyString"
    usage_count 1
  end
end
