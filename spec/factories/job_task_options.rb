FactoryBot.define do
  factory :job_task_option do
    association :job_task
    association :job_option
  end
end
