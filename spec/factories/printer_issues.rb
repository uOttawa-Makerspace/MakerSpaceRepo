FactoryBot.define do
  factory :printer_issue do
    printer { nil }
    summary { "MyString" }
    description { "MyString" }
    user { nil }
    active { false }
  end
end
