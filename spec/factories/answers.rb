FactoryBot.define do
  factory :answer do
    association :question
    description { Faker::Lorem.paragraph }
  end
end
