include ActionDispatch::TestProcess

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
      after(:create) do |repo|
        RepoFile.create(repository_id: repo.id, file: fixture_file_upload(Rails.root.join('spec/support/assets', 'RepoFile1.pdf'), 'application/pdf'))
        Photo.create(repository_id: repo.id, image: fixture_file_upload(Rails.root.join('spec/support/assets', 'avatar.png'), 'image/png'))
      end
    end

    trait :with_equipement_and_categories do
      categories { ['Laser', '3D Printing'] }
      equipments { ['Laser Cutter', '3D Printer'] }
    end

    trait :broken_link do
      youtube_link { "https://google.ca" }
    end

    trait :broken do
      title { "$$$" }
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
