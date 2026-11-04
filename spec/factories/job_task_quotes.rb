FactoryBot.define do
  factory :job_task_quote do
    price { Faker::Number.decimal }
    service_price { Faker::Number.decimal }
    service_quantity { Faker::Number.decimal }
  end
end
