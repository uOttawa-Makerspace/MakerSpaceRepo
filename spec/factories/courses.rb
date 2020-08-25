FactoryBot.define do
  factory :course do
    name { Faker::Name.unique.name }
  end
end
