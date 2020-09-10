FactoryBot.define do
  factory :print_order do
    association :user, :regular_user
    comments { Faker::Lorem.paragraph }
    material { "PLA" }
    approved { false }
    user_approval { false }
    printed { false }
    expedited { false }

    trait :with_file do
      file { FilesTestHelper.stl }
    end

    trait :with_invalid_file do
      file { FilesTestHelper.png }
    end

    trait :with_final_file do
      final_file { FilesTestHelper.stl }
    end

    trait :with_invalid_final_file do
      final_file { FilesTestHelper.png }
    end

    trait :approved do
      approved { true }
      service_charge { 20 }
      grams { 100 }
      quote {}
      price_per_gram { 0.5 }
    end

    trait :declined do
      approved { false }
      staff_comments { Faker::Lorem.paragraph }
    end

    trait :user_approved do
      approved { true }
      service_charge { 20 }
      grams { 100 }
      quote {}
      price_per_gram { 0.5 }
      user_approval { true }
    end
  end
end
