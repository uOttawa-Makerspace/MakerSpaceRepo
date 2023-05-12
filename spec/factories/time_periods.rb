FactoryBot.define do
  factory :time_period do
    name { Faker::Lorem.word }
    start_date { Faker::Date.between(from: 5.days.ago, to: 1.day.ago) }
    end_date { Faker::Date.between(from: 1.day.from_now, to: 5.days.from_now) }
  end
end
