require 'faker'

FactoryBot.define do

  factory :volunteer_task_join do
    association :volunteer_task

    trait :first do
      association :user, :admin
      active { true }
      user_type { "Admin" }
    end

    trait :active do
      association :user, :volunteer
      active { true }
      user_type { "Volunteer" }
    end

    trait :not_active do
      association :user, :volunteer
      active { false }
      user_type { "Volunteer" }
    end

    trait :active_not_volunteer do
      association :user, :admin
      active { true }
      user_type { "Admin" }
    end

    trait :not_active_not_volunteer do
      association :user, :admin
      active { false }
      user_type { "Admin" }
    end

  end

end







