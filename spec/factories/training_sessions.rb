FactoryBot.define do
  factory :training_session do
    association :user, :admin
    association :space
    association :training

    trait :staff_user do
      association :user, :staff
    end

    trait :"3d_printing" do
      association :training, :"3d_printing"
      level {"Beginner"}
    end

    trait :basic_training do
      association :training, :basic_training
      level {"Beginner"}
    end

    factory :training_session_with_certifications do
      transient { certification_count { 2 } }
      after(:create) do |training_session, evaluator|
        create_list(
          :certification,
          evaluator.certification_count,
          training_session: training_session
        )
      end
    end

    factory :training_session_with_exams do
      transient { exam_count { 3 } }
      after(:create) do |training_session, evaluator|
        create_list(
          :exam,
          evaluator.exam_count,
          training_session: training_session
        )
      end
    end

    factory :training_session_with_users do
      after(:create) do |training_session|
        users = 5.times.inject([]) { |arr| arr << create(:user, :regular_user) }
        users.each { |user| training_session.users << user }
      end
    end
  end
end
