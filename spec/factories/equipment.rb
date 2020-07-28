FactoryBot.define do
  factory :equipment do
    association :repository
    name { Faker::Name.name }
  end
end
