FactoryBot.define do
  factory :volunteer_task do
    association :space
    title { Faker::Lorem.word }
    description { Faker::Lorem.paragraph }
    status { "open" }
    joins { 1 }
    category { "Events" }
    cc { 10 }
    hours { 5.00 }
  end
end






