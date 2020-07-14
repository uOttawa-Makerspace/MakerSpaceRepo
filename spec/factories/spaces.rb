FactoryBot.define do
  factory :space do
    name { Faker::Name.unique.name }

    trait :makerspace do
      id { 1 }
      name { "makerspace" }
    end

    trait :makerspace_with_lab_session do
      before(:create) do
        create(:user, :regular_user)
      end

      id { 1 }
      name { "makerspace" }

      after(:create) do |space|
        LabSession.create(user_id: User.last.id, space_id: space.id)
      end
    end

    trait :brunsfield do
      id { 2 }
      name { "Brunsfield" }
    end
  end
end

