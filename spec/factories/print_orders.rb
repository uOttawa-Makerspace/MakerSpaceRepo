require 'faker'

FactoryGirl.define do
  factory :print_order do

    trait :working_print_order do
      id { 1 }
      user_id { 1 }
      comments { Faker::Lorem.paragraph }
      approved { false }
      user_approval { false }
      printed { false }
      expedited { false }
      material { "PLA" }
      file { FilesTestHelper.stl }
    end

    trait :approved_print_order do
      approved { true }
      service_charge { 20 }
      grams { 100 }
      quote {}
      price_per_gram { 0.5 }
    end

    trait :disapproved_print_order do
      approved { false }
      staff_comments { Faker::Lorem.paragraph }
    end

    trait :user_approved_print_order do
      user_approval { true }
    end

    trait :printed_print_order do
      printed { true }
    end

    trait :file_broken_print_order do
      id { 1 }
      user_id { 1 }
      comments { Faker::Lorem.paragraph }
      approved { false }
      user_approval { false }
      printed { false }
      expedited { false }
      material { "PLA" }
      file { FilesTestHelper.png }
    end

    trait :broken_print_order do
      id { 1 }
      comments { Faker::Lorem.paragraph }
      approved { false }
      user_approval { false }
      printed { false }
      expedited { false }
      material { "PLA" }
      file { FilesTestHelper.png }
    end
  end
end
