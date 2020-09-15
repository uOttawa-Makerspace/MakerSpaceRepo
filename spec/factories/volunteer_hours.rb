require 'faker'

FactoryBot.define do

  factory :volunteer_hour do
    association :user, :volunteer_with_volunteer_program
    association :volunteer_task

    trait :approved1 do
      total_time { 10 }
      approval { true }
    end

    trait :not_approved1 do
      total_time { 10 }
      approval { false }
    end

    trait :not_processed do
      total_time { 10 }
      approval { nil }
    end

  end

end









