FactoryBot.define do
  factory :job_quote_line_item do
    association :job_order
    description { Faker::Commerce.product_name }
    price { Faker::Number.decimal(l_digits: 2, r_digits: 2).to_f }
  end
end
