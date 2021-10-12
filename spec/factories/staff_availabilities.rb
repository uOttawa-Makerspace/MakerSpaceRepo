FactoryBot.define do
  factory :staff_availability do
    association :user, :staff
    day {rand(0..7)}
    start_time {Time.now}
    end_time {Time.now + 1.hour}
  end
end
