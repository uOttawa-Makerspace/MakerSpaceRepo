FactoryBot.define do
  factory :staff_availability do
    association :user, :staff
    association :time_period
    day { 1 }
    start_time { Time.current }
    end_time { Time.current + 1.hour }
    recurring { true }
  end
end
