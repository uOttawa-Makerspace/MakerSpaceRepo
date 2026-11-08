FactoryBot.define do
  factory :job_option do
    sequence(:name) { |n| "#{Faker::Lorem.word} #{n}" }
    description { Faker::Lorem.sentence }
    need_files { false }
    fee { 5.0 }
  end
end
