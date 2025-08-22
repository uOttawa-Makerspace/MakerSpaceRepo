FactoryBot.define do
  factory :job_order do
    association :user, :regular_user
    staff_comments { Faker::Lorem.paragraph }

    trait :with_user_files do
      user_files { [FilesTestHelper.stl] }
    end

    trait :with_invalid_user_files do
      user_files { [FilesTestHelper.png] }
    end

    trait :with_staff_files do
      staff_files { [FilesTestHelper.stl] }
    end

    trait :with_invalid_staff_files do
      staff_files { [FilesTestHelper.png] }
    end
  end
end
