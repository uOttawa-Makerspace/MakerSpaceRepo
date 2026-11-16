FactoryBot.define do
  factory :proficient_project_session do
    level { "Beginner" }
    association :certification
    association :user
    association :proficient_project
    
  end
end
