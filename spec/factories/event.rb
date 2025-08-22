FactoryBot.define do
  factory :event do
    title { "Test Event" }
    description { "Test Description" }
    start_time { 1.day.from_now }
    end_time { 1.day.from_now + 2.hours }
    event_type { "meeting" }
    association :space
    association :created_by, factory: :user
    draft { true }

    trait :recurring do
      recurrence_rule { "DTSTART:20250505T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=5" }
    end
  end
end