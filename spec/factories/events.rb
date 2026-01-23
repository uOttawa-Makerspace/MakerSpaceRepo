# spec/factories/events.rb
FactoryBot.define do
  factory :event do
    association :space
    association :created_by, factory: :user
    sequence(:title) { |n| "Event #{n}" }
    event_type { 'meeting' }
    draft { false }
    start_time { Time.zone.now }
    end_time { Time.zone.now + 2.hours }
    description { Faker::Lorem.paragraph }
    recurrence_rule { nil }
    language { nil }
    
    trait :training do
      event_type { 'training' }
      association :training
      association :course_name
      language { 'English' }
      title { 'Training' }
    end

    trait :meeting do
      event_type { 'meeting' }
    end

    trait :recurring do
      recurrence_rule { "DTSTART:20250505T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=5" }
    end

    trait :recurring_weekly do
      recurrence_rule { 'FREQ=WEEKLY;BYDAY=MO;COUNT=4' }
    end

    trait :recurring_daily do
      recurrence_rule { 'FREQ=DAILY;COUNT=7' }
    end

    trait :draft do
      draft { true }
    end

    trait :all_day do
      start_time { Time.zone.now.beginning_of_day }
      end_time { Time.zone.now.beginning_of_day + 1.day }
    end
  end
end