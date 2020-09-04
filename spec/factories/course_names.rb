FactoryBot.define do
  factory :course_name do
    name { Faker::Name.unique.name }
  end
end
