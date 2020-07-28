FactoryBot.define do
  factory :rfid do
    association :user, :regular_user
    card_number { Faker::Alphanumeric.unique.alphanumeric(number: 14) }
    mac_address { Faker::Alphanumeric.unique.alphanumeric(number: 17) }
  end
end
