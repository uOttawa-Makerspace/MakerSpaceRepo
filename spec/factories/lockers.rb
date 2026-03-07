FactoryBot.define do
  factory :locker do
    locker_size
    specifier { Faker::Alphanumeric.alphanumeric }
    available { true }
  end
end
