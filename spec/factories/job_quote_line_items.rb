FactoryBot.define do
  factory :job_quote_line_item do
    association :job_order
    description { Faker::Commerce.product_name }
    price { 25.0 }
  end
end
