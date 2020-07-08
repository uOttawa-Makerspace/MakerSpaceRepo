require 'faker'

FactoryBot.define do
  factory :upvote do
    association :user, :regular_user
    association :comment
  end
end
