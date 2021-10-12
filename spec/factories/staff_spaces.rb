FactoryBot.define do
  factory :staff_space do
    association :user, :staff
    association :space
  end
end
