FactoryBot.define do
  factory :contact_info do
    name { Faker::Name.name }
    email { Faker::Internet.email }
    address { Faker::Address.full_address }
    phone_number { Faker::PhoneNumber.phone_number }
    url { Faker::Internet.url }
  end
end
