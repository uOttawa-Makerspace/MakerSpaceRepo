FactoryBot.define do
  factory :require_training do
    association :training
    association :volunteer_task
  end
end


