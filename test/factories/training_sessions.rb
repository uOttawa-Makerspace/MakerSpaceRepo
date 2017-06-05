# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :training_session do
    name "MyString"
    staff nil
    date "2017-06-05"
    time "2017-06-05 14:15:05"
  end
end
