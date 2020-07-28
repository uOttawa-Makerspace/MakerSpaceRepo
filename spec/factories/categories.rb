FactoryBot.define do
  factory :category do
    association :category_option
    name { Faker::Name.name }

    trait :with_repository do
      association :repository
    end

    trait :with_project_proposal do
      association :project_proposal
    end
  end
end