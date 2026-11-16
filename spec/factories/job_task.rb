FactoryBot.define do
  # A task has no job type or job service until one is chosen; pass them when a spec needs them.
  factory :job_task do
    association :job_order

    sequence(:title) { |n| "Task ##{n}" }
  end
end
