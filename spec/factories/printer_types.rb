FactoryBot.define do
  factory :printer_type do
    trait :UM2P do
      name { "Ultimaker 2+" }
    end
    trait :UM3 do
      name { "Ultimaker 3" }
    end
    trait :RPL2 do
      name { "Replicator 2" }
    end
    trait :Dremel do
      name { "Dremel" }
    end
  end
end
