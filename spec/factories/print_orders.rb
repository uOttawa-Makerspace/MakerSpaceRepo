require 'faker'

FactoryGirl.define do
  factory :print_order do
    id { 1 }
    user_id { 1 }
    comments { Faker::Lorem.paragraph }
    approved { false }
    printed { false }
    expedited { false }
    material { "PLA" }

    trait :with_file do
      file { FilesTestHelper.stl }
    end

    trait :with_wrong_file do
      file { FilesTestHelper.png }
    end
  end
end
