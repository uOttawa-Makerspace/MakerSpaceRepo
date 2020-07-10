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

    trait :approved do
      approved { true }
      service_charge { 20 }
      grams { 100 }
      quote {}
      price_per_gram { 0.5 }
    end

    trait :disapproved do
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

    trait :printed do
      approved { true }
      service_charge { 20 }
      grams { 100 }
      quote {}
      price_per_gram { 0.5 }
      user_approval { true }
      printed { true }
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
