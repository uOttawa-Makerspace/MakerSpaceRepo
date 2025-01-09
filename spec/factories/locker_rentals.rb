FactoryBot.define do
  factory :locker_rental do
    locker_type
    rented_by factory: :user
    state { :reviewing }
    trait :with_notes do
      notes { Faker::Alphanumeric.alpha }
    end

    trait :active do
      state { :active }
      after(:create) do
        locker_specifier do
          Faker::Alphanumeric.unique.numeric(from: 1, to: locker_type.quantity)
        end
      end
      owned_until { Faker::Date.forward }
    end

    trait :await_payment do
      state { :await_payment }
    end
  end
end
