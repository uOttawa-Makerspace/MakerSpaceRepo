FactoryBot.define do
  factory :training_session do
    association :user, :admin
    association :space
    association :training

    trait :'3d_printing' do
      association :training, :'3d_printing'
    end

    trait :basic_training do
      association :training, :basic_training
    end

    factory :training_session_with_certifications do
      transient do
        certification_count { 2 }
      end
      after(:create) do |training_session, evaluator|
        create_list(:certification, evaluator.certification_count, training_session: training_session)
      end
    end

    factory :training_session_with_exams do
      transient do
        exam_count { 3 }
      end
      after(:create) do |training_session, evaluator|
        create_list(:exam, evaluator.exam_count, training_session: training_session)
      end
    end
  end
end



