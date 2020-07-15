FactoryBot.define do
  factory :space do
    name { Faker::Name.unique.name }
  end
end

