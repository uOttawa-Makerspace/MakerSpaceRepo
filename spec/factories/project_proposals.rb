FactoryBot.define do
  factory :project_proposal do

    association :user, :regular_user
    description { Faker::Lorem.paragraph }
    title { Faker::Lorem.word }
    username { Faker::Name.unique.first_name }
    email { Faker::Internet.email }
    client { Faker::Name.name }
    area{ {} }
    client_type { "individual" }
    client_interest { "Low" }
    client_background { "None" }
    supervisor_background {"None" }
    equipments { "Not informed." }

    trait 'normal' do
      youtube_link { "" }
    end

    trait 'bad_link' do
      youtube_link { "https://youtube.com" }
    end

    trait 'good_link' do
      youtube_link { "https://www.youtube.com/watch?v=AbcdeFGHIJLK" }
    end

  end
end
