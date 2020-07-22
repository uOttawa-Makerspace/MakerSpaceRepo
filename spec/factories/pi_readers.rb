FactoryBot.define do
  factory :pi_reader do
    association :space
    pi_mac_address { Faker::Alphanumeric.unique.alphanumeric(number: 17) }
  end
end
