require 'faker'

FactoryGirl.define do

  factory :repository do
    user_id { 1 }
    id { 1 }
    title { Faker::Lorem.word }
    description { Faker::Lorem.paragraph }
    share_type { "public" }
    user_username { "Bob" }
  end

end