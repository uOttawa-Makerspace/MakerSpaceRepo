FactoryBot.define do
  factory :job_service do
    sequence(:name) { |n| "#{Faker::Lorem.word}_#{n}" }
    description { Faker::Lorem.sentence }
    unit { Faker::Lorem.word }
    required { false }
    internal_price { 10.0 }
    external_price { 15.0 }
    association :job_service_group

    trait :with_files do
      files { [FilesTestHelper.stl] }
    end

    trait :with_invalid_files do
      files { [FilesTestHelper.png] }
    end
  end
end
