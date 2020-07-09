require 'faker'

FactoryBot.define do

  factory :comment do

    trait :comment do
      id { 5 }
      repository_id { 1 }
      user_id { 1 }
      content { Faker::Lorem.paragraph }
      upvote { 0 }
      username { "Bob" }
    end

    trait :other_comment do
      id { 6 }
      repository_id { 1 }
      user_id { 1 }
      content { Faker::Lorem.paragraph }
      upvote { 0 }
      username { "Bob" }
    end

  end

end
