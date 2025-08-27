FactoryBot.define do
  factory :space do
    name { Faker::Name.unique.name }
    keycode { Faker::Alphanumeric.alphanumeric(number: 10) }

    trait :with_space_managers do
      after :create do |space|
        2.times do
          space.space_managers << create(:user, :admin)
        end
      end
    end
  end
end
