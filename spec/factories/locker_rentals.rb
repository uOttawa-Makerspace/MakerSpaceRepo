FactoryBot.define do
  factory :locker_rental do
    rented_by factory: :user
    state { :reviewing }
    requested_as { 'general' }

    trait :student do
      requested_as {'student'}
    end
    trait :general do
      requested_as {'general'}
    end
    trait :staff do
      requested_as {'staff'}
    end

    trait :with_repository do
      repository
    end

    trait :notes do
      notes { Faker::Alphanumeric.alpha }
    end

    trait :active do
      locker
      state { :active }
      decided_by factory: :user
      owned_until { Faker::Date.forward }
    end

    trait :await_payment do
      locker
      state { :await_payment }
      decided_by factory: :user
      owned_until { Faker::Date.forward }
    end
  end
end
