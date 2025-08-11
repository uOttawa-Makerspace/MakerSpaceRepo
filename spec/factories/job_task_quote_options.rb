FactoryBot.define do
  factory :job_task_quote_option do
    association :job_option
    association :job_task_quote
    price { Faker::Number.decimal }
  end
end
