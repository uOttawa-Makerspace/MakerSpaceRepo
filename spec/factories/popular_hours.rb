FactoryBot.define do
  factory :popular_hour do
    association :space
    mean { 10.0 }
  end
end
