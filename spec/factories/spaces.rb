FactoryBot.define do
  factory :space do
    name { Faker::Name.unique.name }
    keycode { Faker::Alphanumeric.alphanumeric(number: 10) }
  end
end
