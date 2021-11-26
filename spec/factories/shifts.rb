FactoryBot.define do
  factory :shift do
    association :user, :staff
    association :space
    start_datetime {DateTime.now}
    end_datetime {DateTime.now + 1.hour}
    reason {Faker::Lorem.word}
  end
end
