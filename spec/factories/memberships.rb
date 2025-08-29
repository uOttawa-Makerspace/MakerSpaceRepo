FactoryBot.define do
  factory :membership do
    association :user
    association :membership_tier
    status { 'paid' }
    start_date { Time.current }
    end_date { Time.current + 30.days }
  end
end
