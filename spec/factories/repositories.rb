FactoryBot.define do
  factory :repository do
    title { Faker::Lorem.unique.word }
    description { Faker::Lorem.paragraph }
    share_type { "public" }
    user_username { "Bob" }
    youtube_link { "" }

    trait :private do
      password { "$2a$12$fJ1zqqOdQVXHt6GZVFWyQu2o4ZUU3KxzLkl1JJSDT0KbhfnoGUvg2" } # Password : abc
      share_type { "private" }
    end

    trait :with_repo_files do
      after(:build) do |repo|
        file1 = RepoFile.create(repository_id: repo.id)
        file1.file.attach(io: File.open(Rails.root.join('spec', 'support', 'assets', 'RepoFile1.pdf')), filename: 'RepoFile1.pdf', content_type: 'application/pdf')
        file2 = RepoFile.create(repository_id: repo.id)
        file2.file.attach(io: File.open(Rails.root.join('spec', 'support', 'assets', 'RepoFile2.pdf')), filename: 'RepoFile2.pdf', content_type: 'application/pdf')
      end
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
