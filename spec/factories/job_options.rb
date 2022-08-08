FactoryBot.define do
  factory :job_option do
    name { Faker::Lorem.word }
    description { Faker::Lorem.sentence }
    need_files { false }
    fee { Faker::Number.decimal }
  end
end
