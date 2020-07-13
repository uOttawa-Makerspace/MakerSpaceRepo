require 'faker'

FactoryBot.define do

  factory :volunteer_task_join do
    association :user, :admin_user
    association :volunteer_task

    trait :first do
      active { true }
      user_type { "Admin" }
    end

  end

end







