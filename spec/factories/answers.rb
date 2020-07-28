FactoryBot.define do
  factory :answer do
    association :question
    description { Faker::Lorem.paragraph }

    trait :correct do
      correct { true }
    end

    trait :wrong do
      correct { true }
    end
  end
end