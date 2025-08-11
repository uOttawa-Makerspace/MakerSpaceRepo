FactoryBot.define do
  factory :staff_unavailability do
    user { create(:user, :staff) }
    title { "Unavailable" }
    description { "Unavailable for some reason" }
    start_time { 1.day.from_now }
    end_time { 1.day.from_now + 2.hours }
    recurrence_rule { nil }
  end
end