FactoryBot.define do
  factory :booking_status do
    trait :pending do
      name { "Pending" }
      description { "The booking is pending staff review." }
    end
    trait :approved do
      name { "Approved" }
      description { "The booking has been approved." }
    end
    trait :rejected do
      name { "Declined" }
      description { "The booking has been declined." }
    end
  end
end
