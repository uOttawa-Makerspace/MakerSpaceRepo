# spec/factories/orders.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :order do
    subtotal { 50.000 }
    total { 50.000 }

    order_status do
      OrderStatus.find_by(name: "In progress") || association(:order_status, :in_progress)
    end

    trait :completed do
      order_status do
        OrderStatus.find_by(name: "Completed") || association(:order_status, :completed)
      end
    end

    trait :with_item do
      after(:create) { |order| create(:order_item, order: order) }
    end
  end
end