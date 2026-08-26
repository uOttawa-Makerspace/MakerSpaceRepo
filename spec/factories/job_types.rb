FactoryBot.define do
  factory :job_type do
    sequence(:name) { |n| "#{Faker::Lorem.word}_#{n}" }
    multiple_files { false }
    file_label { Faker::Lorem.word }
    file_description { Faker::Lorem.sentence }
    service_fee { Faker::Number.decimal }
    comments { Faker::Lorem.sentence }
  end
end
