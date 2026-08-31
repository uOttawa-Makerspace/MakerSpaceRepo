# frozen_string_literal: true

FactoryBot.define do
  factory :project_proposal do
    association :user, :regular_user

    description { Faker::Lorem.paragraph }
    sequence(:title) { |n| "Project Proposal #{n}" }
    sequence(:username) { |n| "user#{n}" }
    email { Faker::Internet.email }
    client { Faker::Name.name }
    area { "{}" }
    client_type { "individual" }
    client_interest { "Low" }
    client_background { "None" }
    supervisor_background { "None" }
    equipments { "Not informed." }
    project_cost { Faker::Number.number(digits: 2) }

    trait :normal do
      youtube_link { "" }
    end

    trait :broken do
      title { "A$CD!!!" }
    end

    trait :approved do
      approved { 1 }
      association :admin, factory: %i[user admin]
      youtube_link { "" }
    end

    trait :not_approved do
      approved { 0 }
      youtube_link { "" }
    end

    trait :joined do
      approved { 1 }
      youtube_link { "" }
      after(:create) do |pp|
        ProjectJoin.create!(project_proposal_id: pp.id, user_id: pp.user_id)
      end
    end

    trait :completed do
      approved { 1 }
      youtube_link { "" }
      after(:create) do |pp|
        ProjectJoin.create!(project_proposal_id: pp.id, user_id: pp.user_id)
        create(:repository, project_proposal_id: pp.id, owner: pp.user)
      end
    end

    trait :with_repo_files do
      after(:create) do |pp|
        pp.project_files.attach(
          io: File.open(Rails.root.join("spec/support/assets", "RepoFile1.pdf")),
          filename: "RepoFile1.pdf",
          content_type: "application/pdf"
        )
        pp.photos.attach(
          io: File.open(Rails.root.join("spec/support/assets", "avatar.png")),
          filename: "avatar.png",
          content_type: "image/png"
        )
        pp.reload
      end
    end

    trait :bad_link do
      youtube_link { "https://youtube.com" }
    end

    trait :good_link do
      youtube_link { "https://www.youtube.com/watch?v=AbcdeFGHIJLK" }
    end
  end
end
