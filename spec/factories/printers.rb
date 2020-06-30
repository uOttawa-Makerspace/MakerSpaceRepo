# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :printer do
    trait :UM2P_01 do
      model { "Ultimaker 2+" }
      number { "UM2P - 01" }
    end
    trait :UM2P_02 do
      model { "Ultimaker 2+" }
      number { "UM2P - 02" }
    end
    trait :UM3_01 do
      model { "Ultimaker 3" }
      number { "UM3 - 01" }
    end
    trait :RPL2_01 do
      model { "Replicator 2" }
      number { "RPL2 - 01" }
    end
    trait :RPL2_02 do
      model { "Replicator 2" }
      number { "RPL2 - 02" }
    end
    trait :dremel_10_17 do
      model { 'Dremel' }
      number { "10 - 17" }
    end
  end
end
