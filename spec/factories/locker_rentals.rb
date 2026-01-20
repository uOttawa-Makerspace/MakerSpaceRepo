FactoryBot.define do
  factory :locker_rental do
    association :rented_by, factory: :user
    state { :reviewing }
    requested_as { 'general' }

    trait :student do
      requested_as { 'student' }
    end
    
    trait :general do
      requested_as { 'general' }
    end
    
    trait :staff do
      requested_as { 'staff' }
    end

    trait :with_repository do
      repository
    end

    trait :with_section_information do
      course_name
      section_name { "C3" }
      team_name { "The makerepo design club (tm)" }
    end

    trait :notes do
      notes { "Test note" }
    end

    trait :active do
      association :locker
      state { :active }
      association :decided_by, factory: :user
      owned_until { 30.days.from_now }
    end

    trait :await_payment do
      association :locker
      state { :await_payment }
      association :decided_by, factory: :user
      owned_until { 30.days.from_now }
    end
  end
end
