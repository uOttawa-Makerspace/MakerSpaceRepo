FactoryBot.define do
  factory :job_order_option do
    association :job_order
    association :job_option
  end

  trait :with_option_file do
    option_file { FilesTestHelper.stl }
  end

  trait :with_invalid_option_file do
    option_file { FilesTestHelper.png }
  end
end
