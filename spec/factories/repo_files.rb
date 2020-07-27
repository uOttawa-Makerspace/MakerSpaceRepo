FactoryBot.define do
  factory :repo_file do
    file { FilesTestHelper.pdf }

    trait :in_repository do
      association :repository
    end

    trait :in_proficient_project do
      association :proficient_project
    end

    trait :with_invalid_file do
      file { FilesTestHelper.stl }
    end
  end
end
