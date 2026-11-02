FactoryBot.define do
  factory :job_option do
    sequence(:name) { |n| "#{Faker::Lorem.word} #{n}" }
    description { Faker::Lorem.sentence }
    need_files { false }
    fee { Faker::Number.decimal }
  end
end
