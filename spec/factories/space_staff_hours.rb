FactoryBot.define do
  factory :space_staff_hour do
    association :space
    day { 1 }
    start_time { Time.now }
    end_time { Time.now + 1.hour }
  end
end
