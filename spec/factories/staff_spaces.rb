FactoryBot.define do
  factory :staff_space do
    association :user, :staff
    association :space
    color { '#3788d8' }
  end
end