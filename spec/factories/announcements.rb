FactoryBot.define do
  factory :announcement do

    association :user, :admin_user

    description { Faker::Lorem.paragraph }
    active { true }

    trait 'volunteer' do
      public_goal { "volunteer" }
    end

    trait 'regular_user' do
      public_goal { "regular_user" }
    end

    trait 'staff' do
      public_goal { "staff" }
    end

    trait 'admin' do
      public_goal { "admin" }
    end

    trait 'all' do
      public_goal { "all" }
    end
  end
end
