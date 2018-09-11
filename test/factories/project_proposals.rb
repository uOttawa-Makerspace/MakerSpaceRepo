# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :project_proposal do
    user_id 1
    admin_id 1
    approved 1
    title "MyString"
    description "MyText"
    score 1
    youtube_link "MyString"
  end
end
