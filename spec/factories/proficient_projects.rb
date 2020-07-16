FactoryBot.define do
  factory :proficient_project do
    association :training
    association :badge_template
    title { Faker::Lorem.word }
    description { Faker::Lorem.paragraph }
  end
end