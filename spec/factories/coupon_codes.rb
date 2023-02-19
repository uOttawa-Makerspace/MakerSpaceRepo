FactoryBot.define do
  factory :coupon_code do
    code { Faker::Alphanumeric.alphanumeric(number: 30) }
    dollar_cost { Faker::Number.decimal(l_digits: 2) }
    cc_cost { Faker::Number.number(digits: 2) }

    trait "unclaimed" do
      user nil
    end

    trait "claimed" do
      user { create(:user) }
    end
  end
end
