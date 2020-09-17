FactoryBot.define do
  factory :popular_hour do
    association :space
    mean { Faker::Number.decimal(l_digits: 2, r_digits: 2) }
  end
end
