FactoryBot.define do
  factory :job_type_extra do
    name { Faker::Lorem.word }
    association :job_type
  end
end
