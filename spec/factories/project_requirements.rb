FactoryBot.define do
  factory :project_requirement do
    association :proficient_project
    association :required_project, factory: :proficient_project
  end
end
