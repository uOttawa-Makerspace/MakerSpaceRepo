FactoryBot.define do
  factory :event_assignment do
    association :event
    association :user, :staff
  end
end