FactoryBot.define do
  factory :job_service do
    name { Faker::Lorem.word }
    description { Faker::Lorem.sentence }
    unit { Faker::Lorem.word }
    required { false }
    internal_price { Faker::Number.decimal()}
    external_price { Faker::Number.decimal()}
    association :job_service_group
  end
end
