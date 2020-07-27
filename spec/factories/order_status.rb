FactoryBot.define do
  factory :order_status do
    trait :completed do
      name { "Completed" }
    end

    trait :in_progress do
      name { "In progress" }
    end
  end
end
