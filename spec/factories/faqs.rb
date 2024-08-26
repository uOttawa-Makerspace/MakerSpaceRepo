FactoryBot.define do
  factory :faq do
    title_en { Faker::Alphanumeric.alphanumeric(number: 10) }
    title_fr { Faker::Alphanumeric.alphanumeric(number: 10) }
    body_en { Faker::Alphanumeric.alphanumeric(number: 50) }
    body_fr { Faker::Alphanumeric.alphanumeric(number: 50) }
    order {}
  end
end
