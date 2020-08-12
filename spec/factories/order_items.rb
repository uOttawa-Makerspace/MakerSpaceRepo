FactoryBot.define do
  factory :order_item do

    association :proficient_project
    association :order, :completed

    unit_price { 50.000 }
    total_price { 50.000 }
    quantity { 1 }
    status { "In progress" }

    trait :order_in_progress do
      association :order
    end

    trait :order_in_progress_with_kit do
      association :proficient_project, :with_kit
    end

    trait :awarded do
      status { "Awarded" }
    end

    trait :awarded_with_badge do
      status { "Awarded" }
      association :proficient_project, :with_badge
    end

  end
end
