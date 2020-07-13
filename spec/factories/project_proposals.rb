FactoryBot.define do
  factory :project_proposal do

    association :user, :regular_user

    description { Faker::Lorem.paragraph }
    title { Faker::Lorem.word }
    username { Faker::Name.unique.first_name }
    email { Faker::Internet.email }
    client { Faker::Name.name }
    area { "{}" }
    client_type { "individual" }
    client_interest { "Low" }
    client_background { "None" }
    supervisor_background {"None" }
    equipments { "Not informed." }

    trait 'normal' do
      youtube_link { "" }
    end

    trait 'broken' do
      title { "A$CD!!!" }
    end

    trait 'approved' do
      approved { 1 }
      youtube_link { "" }
    end

    trait 'joined' do
      approved { 1 }
      youtube_link { "" }
      after(:create) do |pp|
        ProjectJoin.create(project_proposal_id: pp.id, user_id: User.last.id)
      end
    end

    trait 'completed' do
      approved { 1 }
      youtube_link { "" }
      after(:create) do |pp|
        ProjectJoin.create(project_proposal_id: pp.id, user_id: User.last.id)
        create(:repository, project_proposal_id: pp.id)
      end
    end

    trait 'bad_link' do
      youtube_link { "https://youtube.com" }
    end

    trait 'good_link' do
      youtube_link { "https://www.youtube.com/watch?v=AbcdeFGHIJLK" }
    end

  end
end
