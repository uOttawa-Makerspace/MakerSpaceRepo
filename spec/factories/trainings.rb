FactoryBot.define do
  factory :training do
    trait :test do
      name { "Test" }
    end

    trait :test2 do
      name { "Test2" }
    end

    trait :'3d_printing' do
      name { "3D Printing" }
    end

    trait :basic_training do
      name { "Basic Training" }
    end
  end
end


