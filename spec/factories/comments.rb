require 'faker'

FactoryBot.define do
  factory :comment do
    association :user, :regular_user
    association :repository
    content { Faker::Lorem.paragraph }
    username { "Bob" }

    factory :comment_with_upvotes do
      transient do
        upvote_count { 5 }
      end
      after(:create) do |comment, evaluator|
        create_list(:upvote, evaluator.upvote_count, comment: comment)
      end
    end
  end
end
