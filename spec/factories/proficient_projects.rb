FactoryBot.define do
  factory :proficient_project do
    association :training

    title { Faker::Lorem.word }
    description { Faker::Lorem.paragraph }
    level { "Beginner" }
    cc { 10 }

    trait :with_files do
      after(:create) do |pp|
        RepoFile.create(
          proficient_project_id: pp.id,
          file:
            Rack::Test::UploadedFile.new(
              Rails.root.join("spec/support/assets/RepoFile1.pdf"),
              "application/pdf"
            )
        )
        Photo.create(
          proficient_project_id: pp.id,
          image:
            Rack::Test::UploadedFile.new(
              Rails.root.join("spec/support/assets/avatar.png"),
              "image/png"
            )
        )
      end
    end

    trait :with_kit do
      has_project_kit { true }
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

    factory :proficient_project_with_project_kits do
      transient { project_kit_count { 3 } }
      after(:create) do |proficient_project, evaluator|
        create_list(
          :project_kit,
          evaluator.project_kit_count,
          proficient_project: proficient_project
        )
      end
    end
  end
end
