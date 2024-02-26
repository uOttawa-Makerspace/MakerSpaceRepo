FactoryBot.define do
  factory :printer_type do
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
  end
end
