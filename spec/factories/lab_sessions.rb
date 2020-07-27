FactoryBot.define do
  factory :lab_session do
    association :space
    association :user, :regular_user
  end
end
