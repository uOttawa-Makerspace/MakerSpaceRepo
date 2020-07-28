FactoryBot.define do
  factory :upvote do
    association :user, :regular_user
    association :comment
    downvote { false }
  end
end
