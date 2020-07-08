require 'faker'

FactoryBot.define do
  factory :repository do
    title { Faker::Lorem.word }
    description { Faker::Lorem.paragraph }
    share_type { "public" }
    user_username { "Bob" }

    factory :repository_with_users do
      transient do
        users_count { 5 }
      end
      after(:create) do |user, evaluator|
        create_list(:repository, evaluator.user_count, users: [user])
      end
    end
  end
end
