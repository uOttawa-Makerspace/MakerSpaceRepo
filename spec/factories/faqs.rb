FactoryBot.define do
  factory :faq do
    title { "MyString" }
    body_en { "MyText" }
    body_fr { "MyText" }
    order { 1 }
  end
end
