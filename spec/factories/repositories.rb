FactoryBot.define do
  factory :repository do
    title { Faker::Lorem.unique.word }
    description { Faker::Lorem.paragraph }
    share_type { "public" }
    user_username { "Bob" }

    trait :private do
      password { "abc" }
      share_type { "private" }
    end

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
