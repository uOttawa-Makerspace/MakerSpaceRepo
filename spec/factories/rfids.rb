FactoryBot.define do
  factory :rfid do
    association :user, :regular_user
    card_number { Faker::Alphanumeric.alphanumeric(number: 14) }
    mac_address { Faker::Alphanumeric.alphanumeric(number: 17) }
  end
end
