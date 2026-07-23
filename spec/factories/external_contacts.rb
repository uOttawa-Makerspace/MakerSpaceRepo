# spec/factories/external_contacts.rb
FactoryBot.define do
  factory :external_contact do
    first_name { Faker::Name.first_name }
    last_name  { Faker::Name.last_name }
    sequence(:email) { |n| "external.holder.#{n}@example.com" }
    phone { "613-555-1234" }
  end
end