FactoryBot.define do
  factory :user do
    read_and_accepted_waiver_form { true }
    active { true }
    email { Faker::Internet.unique.email }
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
        create(:certification, :'3d_printing', user_id: user.id)
        create(:certification, :basic_training, user_id: user.id)
      end
    end

    trait :regular_user_with_avatar do
      after(:build) do |avatar|
        avatar.avatar.attach(io: File.open(Rails.root.join('spec', 'support', 'assets', 'avatar.png')), filename: 'avatar.png', content_type: 'image/png')
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

      after(:create) do |volunteer|
        Skill.create(user_id: volunteer.id, active: true)
      end
    end

    trait :unactive_volunteer do
      role { "volunteer" }

      after(:create) do |volunteer|
        Skill.create(user_id: volunteer.id, active: false)
      end
    end

    trait :volunteer_with_volunteer_program do
      role { "volunteer" }

      after(:create) do |volunteer|
        Program.create(user_id: volunteer.id, program_type: Program::VOLUNTEER)
      end
    end

    trait :volunteer_with_dev_program do
      role { "volunteer" }

      after(:create) do |volunteer|
        Program.create(user_id: volunteer.id, program_type: Program::DEV_PROGRAM)
      end
    end

    trait :student do
      password { "fda3A353$" }
      identity { "undergrad" }
      program { "BASc in Software Engineering" }
      faculty { "Engineering" }
      year_of_study { 2020 }
      student_id { 234139242 }
      gender { "Female" }
    end

    factory :user_with_announcements do
      transient do
        announcements_count { 5 }
      end
      after(:create) do |user, evaluator|
        create_list(:announcement, evaluator.announcements_count, user: user)
      end
    end
  end
end
