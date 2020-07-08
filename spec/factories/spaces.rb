require 'faker'

FactoryBot.define do

  factory :space do

    trait :makerspace do
      id { 1 }
      name { "makerspace" }
    end

    trait :brunsfield do
      id { 2 }
      name { "Brunsfield" }
    end

  end

end

