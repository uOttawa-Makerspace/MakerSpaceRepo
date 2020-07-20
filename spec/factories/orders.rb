FactoryBot.define do
  factory :order do

    subtotal { 50.000 }
    total { 50.000 }

    trait :completed do
      after(:create) do |order|
        order.update(order_status_id: OrderStatus.find_by_name("Completed").id)
      end
    end

  end
end
