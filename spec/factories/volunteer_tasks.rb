require 'faker'

FactoryBot.define do

  factory :volunteer_task do

    trait :first do
      id  { 1 }
      title { Faker::Lorem.word }
      description { Faker::Lorem.paragraph }
      space_id { 1 }
      status { "open" }
      joins { 1 }
      category { "Events" }
      cc { 10 }
      hours { 5.00 }
    end

  end

end






