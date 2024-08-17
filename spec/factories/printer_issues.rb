FactoryBot.define do
  factory :printer_issue do
    association :printer, :Random
    association :reporter, factory: :user
    summary { Faker::Alphanumeric.alphanumeric(number: 10) }
    description { Faker::Alphanumeric.alphanumeric(number: 25) }
    active { true }
    trait :nozzle_clogged do
      summary do
        Faker::Alphanumeric.alphanumeric(number: 10) + " Nozzle clogged."
      end
    end
    trait :bed_issue do
      summary { Faker::Alphanumeric.alphanumeric(number: 10) + " Bed issue." }
    end
    trait :extrude_issue do
      summary do
        Faker::Alphanumeric.alphanumeric(number: 10) + " Extrude issue."
      end
    end
    trait :inactive do
      active { false }
    end
  end
end
