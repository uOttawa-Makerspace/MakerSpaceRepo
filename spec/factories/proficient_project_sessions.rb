FactoryBot.define do
  factory :proficient_project_session do
    association :certification
    association :user
    association :proficient_project
    
  end
end
