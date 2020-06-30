require 'faker'

FactoryGirl.define do

  factory :comment do
    repository_id { 1 }
    user_id { 1 }
    id { 5 }
    content { Faker::Lorem.paragraph }
    upvote { 1 }
    username { "Bob" }
  end

end