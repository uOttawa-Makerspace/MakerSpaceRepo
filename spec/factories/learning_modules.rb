FactoryBot.define do
  factory :learning_module do

    association :training

    title { Faker::Lorem.word }
    description { Faker::Lorem.paragraph }
    level { "Beginner" }

    trait :with_files do
      after(:create) do |pp|
        RepoFile.create(learning_module_id: pp.id, file: fixture_file_upload(Rails.root.join('spec/support/assets', 'RepoFile1.pdf'), 'application/pdf'))
        Photo.create(learning_module_id: pp.id, image: fixture_file_upload(Rails.root.join('spec/support/assets', 'avatar.png'), 'image/png'))
      end
    end

    trait :broken do
      title { "" }
    end

    trait :intermediate do
      level { "Intermediate" }
    end

    trait :advanced do
      level { "Advanced" }
    end
  end

end
