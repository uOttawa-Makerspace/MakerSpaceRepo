FactoryBot.define do
  factory :job_order_quote do
    service_fee { Faker::Number }
  end
end
