FactoryBot.define do
  factory :comment do
    association :user, :regular_user
    association :repository
    content { Faker::Lorem.paragraph }
    username { "Bob" }

    factory :comment_with_upvotes do
      transient { upvote_count { 5 } }
      after(:create) do |comment, evaluator|
        create_list(:upvote, evaluator.upvote_count, comment: comment)
      end
    end
  end
end
