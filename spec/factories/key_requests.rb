FactoryBot.define do
  factory :key_request do
    student_number { Faker::Number.number(digits: 9) }
    phone_number { Faker::Number.number(digits: 10) }
    emergency_contact { Faker::Name.name }
    emergency_contact_phone_number { Faker::Number.number(digits: 10) }
    read_lab_rules { true }
    read_policies { true }
    read_agreement { true }
    user_status { :student }

    trait :status_in_progress do
      status { :in_progress }
    end
    trait :status_waiting_for_approval do
      status { :waiting_for_approval }
    end
    trait :status_approved do
      status { :approved }
    end

    trait :all_questions_answered do
      (1..KeyRequest::NUMBER_OF_QUESTIONS).each do |i|
        sequence("question_#{i}".to_sym) { |n| "Response #{n}" }
      end
    end
  end
end
