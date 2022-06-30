FactoryBot.define do
  factory :job_service_group do
    name { Faker::Lorem.word }
    description { Faker::Lorem.sentence }
    multiple { false}
    text_field { false }
    association :job_type
  end
end
