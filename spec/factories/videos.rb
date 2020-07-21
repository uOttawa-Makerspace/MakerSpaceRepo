FactoryBot.define do
  factory :video do
    association :proficient_project
    direct_upload_url { "" }

    trait :with_video do
      video { FilesTestHelper.mp4 }
    end

    trait :with_invalid_video do
      video { FilesTestHelper.stl }
    end
  end
end
