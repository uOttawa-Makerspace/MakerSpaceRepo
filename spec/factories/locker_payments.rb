FactoryBot.define do
  factory :locker_payment do
    association :locker_rental, factory: %i[locker_rental active]
    sequence(:shopify_order_id) { |n| "9#{n.to_s.rjust(9, '0')}" }
    paid_at { Time.current }
    status { "applied" }
    resolved_at { Time.current }

    trait :held do
      status { "held" }
      hold_reason { "renter_ineligible" }
      resolved_at { nil }
    end
  end
end
