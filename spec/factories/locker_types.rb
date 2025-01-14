FactoryBot.define do
  factory :locker_type do
    short_form { Faker::Alphanumeric.alpha(number: 4) }
    description { Faker::Alphanumeric.alpha }
    available { true }
    available_for { :general }
    quantity { 15 }
    cost { 0.0 }
    trait :not_available do
      available { false }
    end
  end
end
