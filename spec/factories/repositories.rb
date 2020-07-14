FactoryBot.define do
  factory :repository do
    title { Faker::Lorem.unique.word }
    description { Faker::Lorem.paragraph }
    share_type { "public" }
    user_username { "Bob" }
    youtube_link { "" }

    trait :private do
      password { "$2a$12$fJ1zqqOdQVXHt6GZVFWyQu2o4ZUU3KxzLkl1JJSDT0KbhfnoGUvg2" } # Password : ABC
      share_type { "private" }
    end

    trait :broken_link do
      youtube_link { "https://google.ca" }
    end

    trait :working_link do
      youtube_link { "https://www.youtube.com/watch?v=AbcdeFGHIJLK" }
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
