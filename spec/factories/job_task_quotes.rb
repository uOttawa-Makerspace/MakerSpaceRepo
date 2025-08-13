FactoryBot.define do
  factory :job_task_quote do
    price { Faker::Number }
    service_price { Faker::Number }
    service_quantity { Faker::Number }
  end
end
