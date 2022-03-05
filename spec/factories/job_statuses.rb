FactoryBot.define do
  factory :job_status do
    name { Faker::Lorem.word }
    description { Faker::Lorem.sentence }
  end
end
