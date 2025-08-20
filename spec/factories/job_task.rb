FactoryBot.define do
  factory :job_task do
    association :job_order
    association :job_type, optional: true
    association :job_service, optional: true

    sequence(:title) { |n| "Task ##{n}" }
  end
end
