FactoryBot.define do
  factory :order do
    subtotal { 50.000 }
    total { 50.000 }

    before(:create) do
      OrderStatus.find_or_create_by(name: "In progress")
    end

    trait :completed do
      after(:create) do |order|
        order_status = OrderStatus.find_or_create_by(name: "Completed")
        order.update(order_status: order_status)
      end
    end

    trait :with_item do
      after(:create) { |order| create(:order_item, order_id: order.id) }
    end
  end
end