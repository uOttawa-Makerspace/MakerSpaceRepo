FactoryBot.define do
  factory :photo do
    image { FilesTestHelper.png }

    trait :in_repository do
      association :repository
    end

    trait :in_proficient_project do
      association :proficient_project
    end

    trait :with_invalid_image do
      image { FilesTestHelper.stl }
    end
  end
end
