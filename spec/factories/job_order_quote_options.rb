FactoryBot.define do
  factory :job_order_quote_option do
    association :job_option
    association :job_order_quote
    amount { Faker::Number.decimal }
  end
end
