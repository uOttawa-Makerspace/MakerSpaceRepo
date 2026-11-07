FactoryBot.define do
  factory :shadowing_hour do
    start_time { 1.day.from_now.change(min: 0) }
    end_time { start_time + 3.hours }
  end
end
