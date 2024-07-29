FactoryBot.define do
  factory :printer_type do
    # Because setting the same association twice creates it twice
    # unless we create ourselves
    initialize_with do
      PrinterType.find_or_create_by(name: name, short_form: short_form)
    end
    trait :UM2P do
      name { "Ultimaker 2+" }
      short_form { "UM2P" }
    end
    trait :UM3 do
      name { "Ultimaker 3" }
      short_form { "UM3" }
    end
    trait :RPL2 do
      name { "Replicator 2" }
      short_form { "RPL2" }
    end
    trait :Dremel do
      name { "Dremel" }
      short_form { "" }
    end
    trait :Random do
      name { Faker::Alphanumeric.alphanumeric(number: 10) }
      short_form { Faker::Alphanumeric.alphanumeric(number: 4) }
    end
  end
end
