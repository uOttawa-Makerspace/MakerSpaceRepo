FactoryBot.define do
  factory :time_period do
    name { Faker::Lorem.word }
    start_date { 3.days.ago.to_date }
    end_date { 3.days.from_now.to_date }
  end
end
