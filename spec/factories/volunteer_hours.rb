require 'faker'

FactoryBot.define do

  factory :volunteer_hour do

    trait :approved1 do
      total_time { 10 }
      approval { true }
    end

    trait :approved2 do
      total_time { 5 }
      approval { true }
    end

    trait :not_approved1 do
      total_time { 10 }
      approval { false }
    end

  end

end









