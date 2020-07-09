require 'faker'

FactoryBot.define do

  factory :repository do

    trait :repository do
      user_id { 1 }
      id { 1 }
      title { Faker::Lorem.word }
      description { Faker::Lorem.paragraph }
      share_type { "public" }
      user_username { "Bob" }
    end

    trait :private do
      user_id { 1 }
      id { 2 }
      title { Faker::Lorem.word }
      description { Faker::Lorem.paragraph }
      share_type { "private" }
      user_username { "Bob" }
      password { "abc" }
    end

  end
end
