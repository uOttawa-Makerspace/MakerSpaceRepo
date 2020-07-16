FactoryBot.define do
  factory :order do

    subtotal { 50.000 }
    total { 50.000 }
    order_status_id { 1 }

    trait :completed do
      order_status_id { 2 }
    end

  end
end
