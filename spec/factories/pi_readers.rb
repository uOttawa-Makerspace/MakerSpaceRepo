FactoryBot.define do
  factory :pi_reader do
    association :space
    pi_mac_address { Faker::Alphanumeric.unique.alphanumeric(number: 17) }

    after(:create) do |pi_reader|
      pi_reader.update(pi_location: pi_reader.space.name)
    end
  end
end
