FactoryBot.define do
  factory :learning_module do
    association :training

    title { Faker::Lorem.word }
    description { Faker::Lorem.paragraph }
    level { "Beginner" }
    shortcut_name { Faker::Alphanumeric.unique.alphanumeric(number: 8) }

    trait :with_files do
      after(:create) do |pp|
        RepoFile.create(
          learning_module_id: pp.id,
          file:
            Rack::Test::UploadedFile.new(
              Rails.root.join("spec/support/assets", "RepoFile1.pdf"),
              "application/pdf"
            )
        )
        Photo.create(
          learning_module_id: pp.id,
          image:
            Rack::Test::UploadedFile.new(
              Rails.root.join("spec/support/assets", "avatar.png"),
              "image/png"
            )
        )
      end
    end

    trait :with_scorm_object do
      scorm_package { ScormZipHelper.create_scorm_zip }
    end

    trait :with_nested_scorm_object do
      scorm_package { ScormZipHelper.create_scorm_zip(nested_dir: 'scorm_directory') }
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
