FactoryBot.define do
  factory :walk_in_safety_sheet do
    #association :user
    space {Space.first || create(:space)}

    emergency_contact_name { Faker::Name.name }
    emergency_contact_telephone { Faker::PhoneNumber.phone_number }

    trait :is_adult do
      is_minor { false }
      participant_signature { Faker::Name.name }
      participant_telephone_at_home { Faker::PhoneNumber.phone_number }
    end

    trait :missing_adult_info do
      participant_signature { "" }
      participant_telephone_at_home { "" }
    end

    trait :is_minor do
      is_minor { true }
      guardian_signature { Faker::Name.name }
      minor_participant_name { Faker::Name.name }
      guardian_telephone_at_home { Faker::PhoneNumber.phone_number }
      guardian_telephone_at_work { Faker::PhoneNumber.phone_number }
    end

    trait :missing_minor_info do
      is_minor { true }
      guardian_signature { "" }
      minor_participant_name { "" }
      guardian_telephone_at_home { "" }
      guardian_telephone_at_work { "" }
    end

    trait :missing_emergency_info do
      emergency_contact_name { Faker::Name.name }
      emergency_contact_telephone { Faker::PhoneNumber.phone_number }
    end
  end
end
