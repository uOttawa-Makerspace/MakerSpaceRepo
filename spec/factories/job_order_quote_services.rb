FactoryBot.define do
  factory :job_order_quote_service do
    association :job_service
    association :job_order_quote
    quantity { Faker::Number.decimal }
    per_unit { Faker::Number.decimal }
  end
end
