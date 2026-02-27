FactoryBot.define do
  factory :locker_size do
    size { Faker::Alphanumeric.alphanumeric(number: 6) }
    shopify_gid { Faker::Alphanumeric.alphanumeric(number: 12) }
  end
end

