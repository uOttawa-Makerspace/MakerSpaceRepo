# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :order do
    order_status nil
    subtotal "9.99"
    total "9.99"
  end
end
