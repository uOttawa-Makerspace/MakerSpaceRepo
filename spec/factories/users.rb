FactoryBot.define do
  factory :user do
    read_and_accepted_waiver_form { true }
    active { true }
    email { Faker::Internet.unique.username + "@uottawa.ca" }
    name { Faker::Name.name }
    username { Faker::Name.unique.first_name }
    wallet { 1000 }
    confirmed { true }
    password { "$2a$12$t3MkhdxmndlLDLHiJiVqBOdBAjFZWidydW/vd53.pS5ej7DcIZ1LC" }
    role { "regular_user" }
    identity { "community_member" }
    gender { "Male" }

    trait :regular_user do
    end

    trait :regular_user_not_confirmed do
      confirmed { false }
    end
    trait :regular_user_with_certifications do
      after(:create) do |user|
        create(:certification, :"3d_printing", user_id: user.id)
        create(:certification, :basic_training, user_id: user.id)
      end
    end

    trait :regular_user_with_avatar do
      after(:build) do |avatar|
        avatar.avatar.attach(
          io:
            File.open(
              Rails.root.join("spec", "support", "assets", "avatar.png")
            ),
          filename: "avatar.png",
          content_type: "image/png"
        )
      end
    end

    trait :regular_user_with_broken_avatar do
      avatar { AvatarTestHelper.stl }
    end

    trait :admin do
      role { "admin" }
    end

    trait :staff do
      role { "staff" }
    end

    trait :volunteer do
      role { "volunteer" }
    end

    trait :unactive_volunteer do
      role { "volunteer" }
    end

    trait :volunteer_with_volunteer_program do
      role { "volunteer" }

      after(:create) do |volunteer|
        Program.create(user_id: volunteer.id, program_type: Program::VOLUNTEER)
      end
    end

    trait :unactive_volunteer_with_volunteer_program do
      role { "volunteer" }

      after(:create) do |volunteer|
        Program.create(
          user_id: volunteer.id,
          program_type: Program::VOLUNTEER,
          active: false
        )
      end
    end

    trait :volunteer_with_dev_program do
      role { "volunteer" }

      after(:create) do |volunteer|
        Program.create(
          user_id: volunteer.id,
          program_type: Program::DEV_PROGRAM
        )
      end
    end

    trait :student do
      password { "dQxjW4#6fcUF7m!rX" }
      identity { "undergrad" }
      program { "BASc in Software Engineering" }
      faculty { "Engineering" }
      year_of_study { 2020 }
      gender { "Female" }
      student_id { Faker::Number.number(digits: 9) }
    end

    trait :non_engineering do
      program { "Honours BSocSc Political Science " }
      faculty { "Social Sciences" }
    end

    trait :with_staff_spaces do
      # https://thoughtbot.github.io/factory_bot/cookbook/has_many-associations.html
      # Make two spaces
      #create_list(:staff_spaces, 2, user: instance)
      after(:create) do |user|
        2.times { StaffSpace.new(user:, space: create(:space)).save! }
      end
    end

    factory :user_with_announcements do
      transient { announcements_count { 5 } }
      after(:create) do |user, evaluator|
        create_list(:announcement, evaluator.announcements_count, user: user)
      end
    end
  end
end
