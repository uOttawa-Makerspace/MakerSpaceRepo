FactoryBot.define do
  factory :project_kit do
    association :user, :regular_user
    association :proficient_project
    name { Faker::Name.name }

    trait 'delivered' do
      delivered { true }
    end
  end
end
