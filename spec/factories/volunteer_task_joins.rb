require 'faker'

FactoryBot.define do

  factory :volunteer_task_join do

    trait :first do
      id { 1 }
      volunteer_task_id { 1 }
      active { true }
      user_type { "Admin" }
    end

  end

end







