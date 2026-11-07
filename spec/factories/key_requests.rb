FactoryBot.define do
  factory :key_request do
    student_number { "300000001" }
    phone_number { "6135550100" }
    emergency_contact { Faker::Name.name }
    emergency_contact_phone_number { "6135550100" }
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
