require 'faker'

FactoryBot.define do

  factory :volunteer_hour do
    association :user, :regular_user
    association :volunteer_task

    trait :approved1 do
      total_time { 10 }
      approval { true }
    end

    trait :not_approved1 do
      total_time { 10 }
      approval { false }
    end

  end

end









