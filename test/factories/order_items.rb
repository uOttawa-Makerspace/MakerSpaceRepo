# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :order_item do
    proficient_project nil
    order nil
    unit_price "9.99"
    quantity 1
    total_price "9.99"
  end
end
