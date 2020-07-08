require 'rails_helper'

RSpec.describe User, type: :model do

  describe "validation" do

    context 'avatar' do

      it 'should not be valid (wrong filetype)' do
        user = build(:user, :regular_user_with_broken_avatar)
        expect(user.valid?).to be_falsey
      end

      it 'should be valid' do
        user = build(:user, :regular_user)
        expect(user.valid?).to be_truthy
      end

      it 'should be valid' do
        user = build(:user, :regular_user_with_avatar)
        expect(user.valid?).to be_truthy
      end

    end

    context 'name' do

      it 'should not be valid (too long)' do
        user = build(:user, :regular_user)
        user.name = "abcdefghijklmnopqrstuvwxyz abcdefghijklmnopqrstuvwxyz"
        expect(user.valid?).to be_falsey
      end

      it 'should not be valid (nil)' do
        user = build(:user, :regular_user)
        user.name = nil
        expect(user.valid?).to be_falsey
      end

      it 'should be valid' do
        user = build(:user, :regular_user)
        expect(user.valid?).to be_truthy
      end

    end

    context 'username' do

      it 'should not be valid (special characters)' do
        user = build(:user, :regular_user)
        user.username = "gds%%$32"
        expect(user.valid?).to be_falsey
      end

      it 'should not be valid (Too long)' do
        user = build(:user, :regular_user)
        user.username = "abcdefghijklmnopqrstuvwxyz"
        expect(user.valid?).to be_falsey
      end

      it 'should not be valid (Nil)' do
        user = build(:user, :regular_user)
        user.username = nil
        expect(user.valid?).to be_falsey
      end

      it 'should not be valid (uniqueness)' do
        create(:user, :regular_user, id: 5)
        user = build(:user, :regular_user)
        expect(user.valid?).to be_falsey
      end

      it 'should be valid' do
        user = build(:user, :regular_user)
        expect(user.valid?).to be_truthy
      end

    end

    context 'email' do

      it 'should not be valid (nil)' do
        user = build(:user, :regular_user)
        user.email = nil
        expect(user.valid?).to be_falsey
      end

      it 'should not be valid (uniqueness)' do
        user1 = create(:user, :regular_user)
        user2 = build(:user, :regular_user)
        user2.email = user1.email
        expect(user2.valid?).to be_falsey
      end

      it 'should be valid' do
        user = build(:user, :regular_user)
        expect(user.valid?).to be_truthy
      end

    end

    context 'how_heard_about_us' do

      it 'should not be valid (length)' do
        user = build(:user, :regular_user)
        user.how_heard_about_us = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Praesent et mauris vel velit pretium ornare. Donec vitae ligula nunc. Morbi feugiat est in diam ornare ultricies. Sed ultricies feugiat diam, a euismod risus ultrices vitae. Cras posuere purus non pellentesque gravida. Ut sed lorem eu ante id."
        expect(user.valid?).to be_falsey
      end

      it 'should be valid' do
        user = build(:user, :regular_user)
        expect(user.valid?).to be_truthy
      end

    end

    context 'read_and_accepted_waiver_form' do

      it 'should not be valid' do
        user = build(:user, :regular_user)
        user.read_and_accepted_waiver_form = false
        expect(user.valid?).to be_falsey
      end

      it 'should be valid' do
        user = build(:user, :regular_user)
        expect(user.valid?).to be_truthy
      end

    end

    context 'password' do

      it 'should not be valid (format)' do
        user = build(:user, :regular_user)
        user.password = "abc"
        expect(user.valid?).to be_falsey
      end

      it 'should not be valid (nil)' do
        user = build(:user, :regular_user)
        user.password = nil
        expect(user.valid?).to be_falsey
      end

      it 'should be valid' do
        user = build(:user, :regular_user)
        user.password = "abc123ABC123"
        expect(user.valid?).to be_truthy
      end

    end

    context 'gender' do

      it 'should not be valid (format)' do
        user = build(:user, :regular_user)
        user.gender = "abc123"
        expect(user.valid?).to be_falsey
      end

      it 'should not be valid (nil)' do
        user = build(:user, :regular_user)
        user.gender = nil
        expect(user.valid?).to be_falsey
      end

      it 'should be valid' do
        user = build(:user, :regular_user)
        expect(user.valid?).to be_truthy
      end

    end

    context 'faculty' do

      it 'should not be valid (nil)' do
        user = build(:user, :student)
        user.faculty = nil
        expect(user.valid?).to be_falsey
      end

      it 'should be valid' do
        user = build(:user, :regular_user)
        expect(user.valid?).to be_truthy
      end

      it 'should be valid' do
        user = build(:user, :student)
        expect(user.valid?).to be_truthy
      end

    end

    context 'program' do

      it 'should not be valid (nil)' do
        user = build(:user, :student)
        user.program = nil
        expect(user.valid?).to be_falsey
      end

      it 'should be valid' do
        user = build(:user, :regular_user)
        expect(user.valid?).to be_truthy
      end

      it 'should be valid' do
        user = build(:user, :student)
        expect(user.valid?).to be_truthy
      end

    end

    context 'year_of_study' do

      it 'should not be valid (nil)' do
        user = build(:user, :student)
        user.year_of_study = nil
        expect(user.valid?).to be_falsey
      end

      it 'should be valid' do
        user = build(:user, :regular_user)
        expect(user.valid?).to be_truthy
      end

      it 'should be valid' do
        user = build(:user, :student)
        expect(user.valid?).to be_truthy
      end

    end

    context 'student_id' do

      it 'should not be valid (nil)' do
        user = build(:user, :student)
        user.student_id = nil
        expect(user.valid?).to be_falsey
      end

      it 'should be valid' do
        user = build(:user, :regular_user)
        expect(user.valid?).to be_truthy
      end

      it 'should be valid' do
        user = build(:user, :student)
        expect(user.valid?).to be_truthy
      end

    end

    context 'identity' do

      it 'should not be valid (nil)' do
        user = build(:user, :regular_user)
        user.identity = nil
        expect(user.valid?).to be_falsey
      end

      it 'should not be valid (wrong identity)' do
        user = build(:user, :regular_user)
        user.identity = "Something else"
        expect(user.valid?).to be_falsey
      end

      it 'should be valid' do
        user = build(:user, :regular_user)
        expect(user.valid?).to be_truthy
      end

    end

  end

  describe "scopes" do

    context 'no_waiver_users' do

      it 'should return nothing' do
        create(:user, :regular_user)
        expect(User.no_waiver_users.count).to eq(0)
      end

    end

    context 'between_dates_picked' do

      it 'should return one' do
        create(:user, :regular_user, created_at: '2017-07-07 19:15:39.406247')
        start_date = DateTime.new(2016,2,3,4,5,6)
        end_date = DateTime.new(2018,2,3,4,5,6)
        expect(User.between_dates_picked(start_date, end_date).count).to eq(1)
      end

      it 'should return one' do
        create(:user, :regular_user, created_at: '2020-07-07 19:15:39.406247')
        start_date = DateTime.new(2019,2,3,4,5,6)
        end_date = DateTime.new(2020,2,3,4,5,6)
        expect(User.between_dates_picked(start_date, end_date).count).to eq(0)
      end

    end

    context 'active' do

      it 'should return 2 active users' do
        create(:user, :regular_user)
        create(:user, :admin_user)
        expect(User.active.count).to eq(2)
      end

      it 'should return 1 active user' do
        create(:user, :regular_user)
        create(:user, :admin_user, active: false)
        expect(User.active.count).to eq(1)
      end

    end

    context 'unknown_identity' do

      it 'should return 0 users' do
        create(:user, :regular_user)
        create(:user, :admin_user)
        expect(User.unknown_identity.count).to eq(0)
      end

      it 'should return 1 user' do
        create(:user, :regular_user)
        create(:user, :admin_user, identity: "unknown")
        expect(User.unknown_identity.count).to eq(1)
      end

    end

  end

  describe 'model methods' do

    context 'display_avatar' do

      it 'should get the avatar' do
        create(:user, :regular_user_with_avatar)
        expect(User.display_avatar(User.find(1)).filename).to eq("avatar.png")
      end

      it 'should get the default avatar' do
        create(:user, :regular_user)
        expect(User.display_avatar(User.find(1))).to eq("default-avatar.png")
      end

    end

    context 'username_or_email' do

      it 'should return nothing' do
        create(:user, :regular_user, email: "a@b.com")
        expect(User.username_or_email("abc")).to be_nil
      end

      it 'should return the user (by email)' do
        create(:user, :regular_user, email: "a@b.com")
        expect(User.username_or_email("a@b.com").id).to eq(1)
      end

      it 'should return the user (by username)' do
        create(:user, :regular_user)
        expect(User.username_or_email("Bob").id).to eq(1)
      end

    end

    context 'authenticate' do

      it 'should return nothing' do
        create(:user, :regular_user, email: "a@b.com")
        expect(User.authenticate("a@b.com", "false")).to be_nil
      end

      it 'should return the user' do
        create(:user, :regular_user, email: "a@b.com")
        expect(User.authenticate("a@b.com", "asa32A353#").id).to eq(1)
      end

    end

    context 'student?' do
      it 'should return false' do
        user = create(:user, :regular_user)
        expect(user.student?).to be_falsey
      end

      it 'should return true' do
        user = create(:user, :student)
        expect(user.student?).to be_truthy
      end
    end

    context 'admin?' do
      it 'should return false' do
        user = create(:user, :regular_user)
        expect(user.admin?).to be_falsey
      end

      it 'should return true' do
        user = create(:user, :admin_user)
        expect(user.admin?).to be_truthy
      end
    end

    context 'staff?' do
      it 'should return false' do
        user = create(:user, :regular_user)
        expect(user.staff?).to be_falsey
      end

      it 'should return true' do
        user = create(:user, :staff)
        expect(user.staff?).to be_truthy
      end
    end

    context 'volunteer?' do
      it 'should return false' do
        user = create(:user, :regular_user)
        expect(user.volunteer?).to be_falsey
      end

      it 'should return true' do
        user = create(:user, :volunteer)
        expect(user.volunteer?).to be_truthy
      end
    end

    context 'volunteer_program?' do
      it 'should return false' do
        user = create(:user, :volunteer)
        expect(user.volunteer_program?).to be_falsey
      end

      it 'should return true' do
        user = create(:user, :volunteer)
        Program.create(user_id: user.id, program_type: Program::VOLUNTEER)
        expect(user.volunteer_program?).to be_truthy
      end
    end

    context 'dev_program?' do
      it 'should return false' do
        user = create(:user, :volunteer)
        expect(user.dev_program?).to be_falsey
      end

      it 'should return true' do
        user = create(:user, :volunteer)
        Program.create(user_id: user.id, program_type: Program::DEV_PROGRAM)
        expect(user.dev_program?).to be_truthy
      end
    end

    context 'location' do
      it 'should return no sign in yet' do
        user = create(:user, :regular_user)
        expect(user.location).to eq("no sign in yet")
      end

      it 'should return makerspace' do
        user = create(:user, :regular_user)
        create(:space, :makerspace)
        LabSession.create(user_id: user.id, space_id: 1)
        expect(user.location).to eq("makerspace")
      end
    end

    context 'get_total_cc' do
      it 'should return 0' do
        user = create(:user, :regular_user)
        expect(user.get_total_cc).to eq(0)
      end

      it 'should return 100' do
        user = create(:user, :regular_user)
        create(:cc_money, :hundred, user_id: user.id)
        expect(user.get_total_cc).to eq(100)
      end
    end

    context 'get_total_hours' do
      it 'should return 0 hours' do
        user = create(:user, :regular_user)
        task = create(:volunteer_task, :first, user_id: user.id)
        create(:volunteer_hour, :not_approved1, user_id: user.id, volunteer_task_id: task.id)
        expect(user.get_total_hours).to eq(0)
      end

      it 'should return 15 hours' do
        user = create(:user, :regular_user)
        task = create(:volunteer_task, :first, user_id: user.id)
        create(:volunteer_hour, :approved1, user_id: user.id, volunteer_task_id: task.id)
        create(:volunteer_hour, :approved2, user_id: user.id, volunteer_task_id: task.id)
        create(:volunteer_hour, :not_approved1, user_id: user.id, volunteer_task_id: task.id)
        expect(user.get_total_hours).to eq(15)
      end
    end

    context 'update_wallet' do

      it 'should update wallet to a 100' do
        user = create(:user, :regular_user)
        create(:cc_money, :hundred, user_id: user.id)
        user.update_wallet
        expect(user.wallet).to eq(100)
      end
    end

    context 'get_certifications_names' do

      it 'should get all certifications' do
        user = create(:user, :admin_user)
        create(:space, :makerspace)
        create(:training, :test)
        create(:training_session, :normal, user_id: user.id)
        create(:certification, :first, user_id: user.id)
        expect(user.get_certifications_names).to eq(['Test'])
      end
    end

    context 'get_volunteer_tasks_from_volunteer_joins' do

      it 'should get all volunteer tasks' do
        user = create(:user, :admin_user)
        create(:space, :makerspace)
        create(:volunteer_task, :first, user_id: user.id)
        create(:volunteer_task_join, :first, user_id: user.id)
        expect(user.get_volunteer_tasks_from_volunteer_joins.first.id).to eq(VolunteerTask.last.id)
      end
    end

    context 'get_badges' do

      it 'should get badge called none' do
        user = create(:user, :admin_user)
        create(:space, :makerspace)
        training = create(:training, :test)
        expect(user.get_badges(training.id)).to eq('badges/none.png')
      end

      it 'should get badge called bronze' do
        user = create(:user, :admin_user)
        create(:space, :makerspace)
        training = create(:training, :test)
        create(:training_session, :normal, user_id: user.id)
        create(:certification, :first, user_id: user.id)
        expect(user.get_badges(training.id)).to eq('badges/bronze.png')
      end

    end

    context 'remaining_trainings' do

      it 'should get the two remaining trainings' do
        user = create(:user, :admin_user)
        create(:space, :makerspace)
        create(:training, :test)
        create(:training, :test2)
        expect(user.remaining_trainings.ids).to eq([1,2])
      end

      it 'should get the remaining training' do
        user = create(:user, :admin_user)
        create(:space, :makerspace)
        create(:training, :test)
        create(:training, :test2)
        create(:training_session, :normal, user_id: user.id)
        create(:certification, :first, user_id: user.id)
        expect(user.remaining_trainings.ids).to eq([2])
      end

    end

    context 'return_program_status' do

      it 'should return status 0' do
        user = create(:user, :regular_user)
        create(:space, :makerspace)
        expect(user.return_program_status).to eq(0)
      end

      it 'should return status 1' do
        user = create(:user, :regular_user)
        staff = create(:user, :staff)
        create(:space, :makerspace)
        create(:training, :three_d)
        create(:training_session, :three_d, user_id: staff.id)
        create(:certification, :three_d, user_id: user.id)
        create(:space, :brunsfield)
        create(:training, :basic)
        create(:training_session, :basic, user_id: staff.id)
        create(:certification, :basic, user_id: user.id)
        expect(user.return_program_status).to eq(1)
      end

      it 'should return status 2' do
        user = create(:user, :regular_user)
        staff = create(:user, :staff)
        create(:space, :makerspace)
        create(:training, :three_d)
        create(:training_session, :three_d, user_id: staff.id)
        create(:certification, :three_d, user_id: user.id)
        create(:space, :brunsfield)
        create(:training, :basic)
        create(:training_session, :basic, user_id: staff.id)
        create(:certification, :basic, user_id: user.id)
        Program.create(user_id: user.id, program_type: Program::VOLUNTEER)
        expect(user.return_program_status).to eq(2)
      end

      it 'should return status 2' do
        volunteer = create(:user, :volunteer)
        staff = create(:user, :staff)
        create(:space, :makerspace)
        create(:training, :three_d)
        create(:training_session, :three_d, user_id: staff.id)
        create(:certification, :three_d, user_id: volunteer.id)
        create(:space, :brunsfield)
        create(:training, :basic)
        create(:training_session, :basic, user_id: staff.id)
        create(:certification, :basic, user_id: volunteer.id)
        expect(volunteer.return_program_status).to eq(2)
      end

      it 'should return status 3' do
        user = create(:user, :regular_user)
        staff = create(:user, :staff)
        create(:space, :makerspace)
        create(:training, :three_d)
        create(:training_session, :three_d, user_id: staff.id)
        create(:certification, :three_d, user_id: user.id)
        create(:space, :brunsfield)
        create(:training, :basic)
        create(:training_session, :basic, user_id: staff.id)
        create(:certification, :basic, user_id: user.id)
        Program.create(user_id: user.id, program_type: Program::DEV_PROGRAM)
        expect(user.return_program_status).to eq(3)
      end

      it 'should return status 4' do
        volunteer = create(:user, :volunteer)
        staff = create(:user, :staff)
        create(:space, :makerspace)
        create(:training, :three_d)
        create(:training_session, :three_d, user_id: staff.id)
        create(:certification, :three_d, user_id: volunteer.id)
        create(:space, :brunsfield)
        create(:training, :basic)
        create(:training_session, :basic, user_id: staff.id)
        create(:certification, :basic, user_id: volunteer.id)
        Program.create(user_id: volunteer.id, program_type: Program::DEV_PROGRAM)
        expect(volunteer.return_program_status).to eq(4)
      end

      it 'should return status 4' do
        user = create(:user, :regular_user)
        staff = create(:user, :staff)
        create(:space, :makerspace)
        create(:training, :three_d)
        create(:training_session, :three_d, user_id: staff.id)
        create(:certification, :three_d, user_id: user.id)
        create(:space, :brunsfield)
        create(:training, :basic)
        create(:training_session, :basic, user_id: staff.id)
        create(:certification, :basic, user_id: user.id)
        Program.create(user_id: user.id, program_type: Program::VOLUNTEER)
        Program.create(user_id: user.id, program_type: Program::DEV_PROGRAM)
        expect(user.return_program_status).to eq(4)
      end

    end

    context 'has_required_badges?' do

      before :each do
        create(:badge_template, :three_d_printing)
        create(:badge_template, :laser_cutting)
        create(:badge_template, :arduino)
      end

      it 'should be false' do
        user = create(:user, :regular_user)
        create(:badge_requirement, :three_d_printing)
        expect(user.has_required_badges?(BadgeRequirement.all)).to be_falsey
      end

      it 'should be true' do
        user = create(:user, :regular_user)
        create(:badge, :three_d_printing, user_id: user.id)
        create(:badge_requirement, :three_d_printing)
        expect(user.has_required_badges?(BadgeRequirement.all)).to be_truthy
      end

      it 'should be true' do
        user = create(:user, :regular_user)
        create(:badge, :three_d_printing, user_id: user.id)
        create(:badge_requirement, :three_d_printing)
        create(:badge, :laser_cutting, user_id: user.id)
        create(:badge_requirement, :laser_cutting)
        create(:badge, :arduino, user_id: user.id)
        expect(user.has_required_badges?(BadgeRequirement.all)).to be_truthy
      end

    end

  end

end
