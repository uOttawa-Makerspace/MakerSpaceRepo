FactoryBot.define do
  factory :order_item do

    association :proficient_project
    association :order, :completed

    unit_price { 50.000 }
    total_price { 50.000 }
    quantity { 1 }
    status { "In progress" }

    trait :awarded do
      status { "Awarded" }
    end

  end
end
