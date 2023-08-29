FactoryBot.define do
  factory :key do
    sequence(:number) { |n| n }
    custom_keycode { Faker::Alphanumeric.alphanumeric(number: 10) }

    trait :regular_key_type do
      key_type { :regular }
    end
    trait :sub_master_key_type do
      key_type { :sub_master }
    end
    trait :keycard_key_type do
      key_type { :keycard }
    end

    trait :unknown_status do
      status { :unknown }
    end
    trait :inventory_status do
      status { :inventory }
    end
    trait :held_status do
      status { :held }
    end
    trait :lost_status do
      status { :lost }
    end
  end
end
