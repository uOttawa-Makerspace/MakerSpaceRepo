FactoryBot.define do
  factory :sub_space do
    name { Faker::Lorem.word }
    space { create(:space) }
  end
end
