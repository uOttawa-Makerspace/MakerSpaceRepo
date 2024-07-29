FactoryBot.define do
  factory :printer do
    trait :UM2P_01 do
      association :printer_type, :UM2P
      number { "01" }
    end
    trait :UM2P_02 do
      association :printer_type, :UM2P
      number { "02" }
    end
    trait :UM3_01 do
      association :printer_type, :UM3
      number { "01" }
    end
    trait :RPL2_01 do
      association :printer_type, :RPL2
      number { "01" }
    end
    trait :RPL2_02 do
      association :printer_type, :RPL2
      number { "02" }
    end
    trait :dremel_10_17 do
      association :printer_type, :Dremel
      number { "17" }
    end
  end
end
