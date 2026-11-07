require "faker"

FactoryBot.define do
  factory :volunteer_task_join do
    association :volunteer_task

    trait :first do
      association :user, :admin
      active { true }
      state { "joined" }
      user_type { "Admin" }
    end

    trait :active do
      association :user, :volunteer
      active { true }
      state { "joined" }
      user_type { "Volunteer" }
    end

    trait :not_active do
      association :user, :volunteer
      active { false }
      state { "removed" }
      user_type { "Volunteer" }
    end

    trait :completed do
      association :user, :volunteer
      active { false }
      state { "completed" }
      state_changed_at { Time.current }
      user_type { "Volunteer" }
    end

    trait :left do
      association :user, :volunteer
      active { false }
      state { "left" }
      state_changed_at { Time.current }
      user_type { "Volunteer" }
    end

    trait :active_not_volunteer do
      association :user, :admin
      active { true }
      state { "joined" }
      user_type { "Admin" }
    end

    trait :not_active_not_volunteer do
      association :user, :admin
      active { false }
      state { "removed" }
      user_type { "Admin" }
    end
  end
end
