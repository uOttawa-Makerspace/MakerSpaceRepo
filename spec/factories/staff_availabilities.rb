FactoryBot.define do
  factory :staff_availability do
    association :user, :staff
    association :time_period
    day { rand(0..7) }
    start_time { Time.now }
    end_time { Time.now + 1.hour }
    recurring { true }
  end
end
