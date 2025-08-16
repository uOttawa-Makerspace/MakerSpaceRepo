FactoryBot.define do
  factory :locker_rental do
    locker_type
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
      transient { locker_specifier { locker_type.get_available_lockers.first } }
      state { :active }
      before(:create) do |rental, context|
        rental.locker_specifier = context.locker_specifier
        # This throws a retry limit error after it passes the locker_type limit
        #Faker::Number.unique.between(from: 1, to: rental.locker_type.quantity)
      end
      owned_until { Faker::Date.forward }
    end

    trait :await_payment do
      state { :await_payment }
    end
  end
end
