require 'faker'

FactoryBot.define do

  factory :training do

    trait :test do
      id { 1 }
      name { "Test" }
    end

    trait :test2 do
      id { 2 }
      name { "Test2" }
    end

    trait :three_d do
      id { 3 }
      name { "3D Printing" }
    end

    trait :basic do
      id { 4 }
      name { "Basic Training" }
    end

  end

end


