FactoryBot.define do
  factory :makerstore_link do
    title { Faker::Alphanumeric.alphanumeric(number: 10) }
    url { Faker::Internet.url }
    shown { true }
    order { 0 }
    trait :with_image do
      image { FilesTestHelper.png }
    end

    trait :hidden do
      shown { false }
    end
  end
end
