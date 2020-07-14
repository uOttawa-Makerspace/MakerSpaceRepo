FactoryBot.define do
  factory :exam do
    association :user, :regular_user
    association :training_session, :basic_training
    category { "Basic Training" }
    status { Exam::STATUS[:not_started] }
    expired_at { DateTime.tomorrow.end_of_day }
  end
end