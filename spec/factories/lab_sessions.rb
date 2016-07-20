# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :lab_session do
    rfid "MyString"
    sign_in_time "2016-07-13 13:47:53"
    sign_out_time "2016-07-13 13:47:53"
  end
end
