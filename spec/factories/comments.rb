require 'faker'

FactoryGirl.define do
  factory :comment do
    id 1
    content { Faker::Lorem.words }
    upvote 1
    username { Faker::Lorem.word }
    after(:create) do
      create(:repo1)
      create(:user1)
    end
  end

  factory :other_comment do
    id 2
    user_id 2
    content { Faker::Lorem.words }
    upvote 1
    username { Faker::Lorem.word }
  end
end