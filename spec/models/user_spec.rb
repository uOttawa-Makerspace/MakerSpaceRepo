require 'rails_helper'
include BCrypt
include ActiveModel::Serialization

RSpec.describe User, type: :model do

  describe 'Association' do

    context 'has_one' do
      it { should have_one(:rfid) }
      it { should have_one(:skill) }
      it { should have_one(:volunteer_request) }
    end

    context 'accepts_nested_attributes_for' do
      it { should accept_nested_attributes_for(:repositories) }
    end

    context 'has_and_belongs_to_many' do
      it { should have_and_belong_to_many(:repositories) }
      it { should have_and_belong_to_many(:training_sessions) }
      it { should have_and_belong_to_many(:proficient_projects) }
    end

    context 'has_many' do
      it { should have_many(:upvotes) }
      it { should have_many(:comments) }
      it { should have_many(:certifications) }
      it { should have_many(:lab_sessions) }
      it { should have_many(:project_proposals) }
      it { should have_many(:project_joins) }
      it { should have_many(:printer_sessions) }
      it { should have_many(:volunteer_hours) }
      it { should have_many(:volunteer_task_joins) }
      it { should have_many(:training_sessions) }
      it { should have_many(:announcements) }
      it { should have_many(:questions) }
      it { should have_many(:exams) }
      it { should have_many(:print_orders) }
      it { should have_many(:volunteer_task_requests) }
      it { should have_many(:cc_moneys) }
      it { should have_many(:badges) }
      it { should have_many(:programs) }
      it { should have_many(:orders) }
      it { should have_many(:order_items) }
      it { should have_many(:discount_codes) }
    end
  end

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

      it { should validate_length_of(:name).is_at_most(50) }
      it { should validate_presence_of(:name) }

    end

    context 'username' do

      it { should_not allow_value("gds%%$32").for(:username) }
      it { should allow_value("johndoe").for(:username) }
      it { should validate_length_of(:username).is_at_most(20) }
      it { should validate_presence_of(:username) }
      it { should validate_uniqueness_of(:username) }

    end

    context 'email' do

      it { should validate_presence_of(:email) }
      it { should validate_uniqueness_of(:email) }

    end

    context 'how_heard_about_us' do

      it { should validate_length_of(:how_heard_about_us).is_at_most(250) }

    end

    context 'read_and_accepted_waiver_form' do

      it { should_not allow_value(false).for(:read_and_accepted_waiver_form) }
      it { should allow_value(true).for(:read_and_accepted_waiver_form) }

    end

    context 'password' do

      it { should_not allow_value('abc').for(:password) }
      it { should allow_value("AbCdE123").for(:password) }
      it { should validate_presence_of(:password) }

    end

    context 'gender' do

      it { should_not allow_value("Something else").for(:gender) }
      it { should allow_value('Male', 'Female', 'Other', 'Prefer not to specify', 'unknown').for(:gender) }
      it { should validate_presence_of(:gender) }

    end

    context 'faculty student' do

      subject { build(:user, :student, faculty: nil) }
      it { should validate_presence_of(:faculty) }

    end

    context 'faculty non-student' do

      subject { build(:user, :regular_user, faculty: nil) }
      it { should_not validate_presence_of(:faculty) }

    end

    context 'program student' do

      subject { build(:user, :student, program: nil) }
      it { should validate_presence_of(:program) }

    end

    context 'program non-student' do

      subject { build(:user, :regular_user, program: nil) }
      it { should_not validate_presence_of(:program) }

    end

    context 'year_of_study student' do

      subject { build(:user, :student, year_of_study: nil) }
      it { should validate_presence_of(:year_of_study) }

    end

    context 'year_of_study non-student' do

      subject { build(:user, :regular_user, year_of_study: nil) }
      it { should_not validate_presence_of(:year_of_study) }

    end

    context 'student_id student' do

      subject { build(:user, :student, student_id: nil) }
      it { should validate_presence_of(:student_id) }

    end

    context 'student_id non-student' do

      subject { build(:user, :regular_user, student_id: nil) }
      it { should_not validate_presence_of(:student_id) }

    end

    context 'identity' do

      it { should validate_presence_of(:identity) }
      it { should_not allow_value("Something else").for(:identity) }
      it { should allow_value('grad', 'undergrad', 'faculty_member', 'community_member', 'unknown').for(:identity) }

    end

  end

  describe "scopes" do

    before :all do
      create(:user, :regular_user)
      create(:user, :regular_user)
      create(:user, :admin)
      create(:user, :staff)
      create(:user, :volunteer)
    end

    context '#no_waiver_users' do

      it 'should return nothing' do
        expect(User.no_waiver_users.count).to eq(0)
      end

    end

    context '#between_dates_picked' do

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

    context '#active' do

      it 'should return 5 active users' do
        expect(User.active.count).to eq(User.all.count)
      end

      it 'should return 5 active user' do
        create(:user, :admin, active: false)
        expect(User.active.count).to eq(User.all.count - 1)
      end

    end

    context '#unknown_identity' do

      it 'should return 0 users' do
        expect(User.unknown_identity.count).to eq(0)
      end

      it 'should return 1 user' do
        create(:user, :admin, identity: "unknown")
        expect(User.unknown_identity.count).to eq(1)
      end

    end

  end

  describe 'model methods' do

    context '#display_avatar' do

      it 'should get the avatar' do
        user = create(:user, :regular_user_with_avatar)
        expect(User.display_avatar(User.find(user.id)).filename).to eq("avatar.png")
      end

      it 'should get the default avatar' do
        user = create(:user, :regular_user)
        expect(User.display_avatar(User.find(user.id))).to eq("default-avatar.png")
      end

    end

    context '#username_or_email' do

      it 'should return nothing' do
        create(:user, :regular_user, email: "a@b.com")
        expect(User.username_or_email("abc")).to be_nil
      end

      it 'should return the user (by email)' do
        user = create(:user, :regular_user)
        expect(User.username_or_email(user.email).id).to eq(user.id)
      end

      it 'should return the user (by username)' do
        user = create(:user, :regular_user)
        expect(User.username_or_email(user.username).id).to eq(user.id)
      end

    end

    context '#authenticate' do

      it 'should return nothing' do
        create(:user, :regular_user, email: "a@b.com")
        expect(User.authenticate("a@b.com", 'somethingelse')).to be_nil
      end

      it 'should return the user' do
        user = create(:user, :regular_user, email: "a@b.com")
        expect(User.authenticate("a@b.com", 'asa32A353#').id).to eq(user.id)
      end

    end

    context '#student?' do
      it 'should return false' do
        user = create(:user, :regular_user)
        expect(user.student?).to be_falsey
      end

      it 'should return true' do
        user = create(:user, :student)
        expect(user.student?).to be_truthy
      end
    end

    context '#admin?' do
      it 'should return false' do
        user = create(:user, :regular_user)
        expect(user.admin?).to be_falsey
      end

      it 'should return true' do
        user = create(:user, :admin)
        expect(user.admin?).to be_truthy
      end
    end

    context '#staff?' do
      it 'should return false' do
        user = create(:user, :regular_user)
        expect(user.staff?).to be_falsey
      end

      it 'should return true' do
        user = create(:user, :staff)
        expect(user.staff?).to be_truthy
      end
    end

    context '#volunteer?' do
      it 'should return false' do
        user = create(:user, :regular_user)
        expect(user.volunteer?).to be_falsey
      end

      it 'should return true' do
        user = create(:user, :volunteer)
        expect(user.volunteer?).to be_truthy
      end
    end

    context '#volunteer_program?' do
      it 'should return false' do
        user = create(:user, :volunteer)
        expect(user.volunteer_program?).to be_falsey
      end

      it 'should return true' do
        user = create(:user, :volunteer_with_volunteer_program)
        expect(user.volunteer_program?).to be_truthy
      end
    end

    context '#dev_program?' do
      it 'should return false' do
        user = create(:user, :volunteer)
        expect(user.dev_program?).to be_falsey
      end

      it 'should return true' do
        user = create(:user, :volunteer_with_dev_program)
        expect(user.dev_program?).to be_truthy
      end
    end

    context '#location' do
      it 'should return no sign in yet' do
        user = create(:user, :regular_user)
        expect(user.location).to eq("no sign in yet")
      end

      it 'should return makerspace' do
        user = create(:user, :regular_user)
        space = create(:space)
        LabSession.create(user: user, space: space)
        expect(user.location).to eq(space.name)
      end
    end

    context '#get_total_cc' do
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

    context '#get_total_hours' do
      it 'should return 0 hours' do
        create(:volunteer_hour, :not_approved1)
        expect(User.last.get_total_hours).to eq(0)
      end

      it 'should return 15 hours' do
        create(:volunteer_hour, :approved1)
        expect(User.last.get_total_hours).to eq(10)
      end
    end

    context '#update_wallet' do

      it 'should update wallet to a 100' do
        user = create(:user, :regular_user)
        create(:cc_money, :hundred, user_id: user.id)
        user.update_wallet
        expect(user.wallet).to eq(100)
      end
    end

    context '#get_certifications_names' do

      it 'should get all certifications' do
        user = create(:user, :admin)
        create(:training, :test2)
        create(:certification, :first, user_id: user.id)
        expect(user.get_certifications_names).to eq(['Test'])
      end
    end

    context '#get_volunteer_tasks_from_volunteer_joins' do

      it 'should get all volunteer tasks' do
        create(:volunteer_task_join, :first)
        expect(User.last.get_volunteer_tasks_from_volunteer_joins.first.id).to eq(VolunteerTask.last.id)
      end
    end

    context '#get_badges' do

      it 'should get badge called none' do
        user = create(:user, :admin)
        training = create(:training, :test)
        expect(user.get_badges(training.id)).to eq('badges/none.png')
      end

      it 'should get badge called bronze' do
        user = create(:user, :regular_user)
        create(:certification, :first, user_id: user.id)
        expect(user.get_badges(Training.last.id)).to eq('badges/bronze.png')
      end

    end

    context '#remaining_trainings' do

      it 'should get the two remaining trainings' do
        user = create(:user, :admin)
        training1 = create(:training, :test)
        training2 = create(:training, :test2)
        expect(user.remaining_trainings.ids).to eq([training1.id,training2.id])
      end

      it 'should get the remaining training' do
        user = create(:user, :admin)
        training = create(:training, :test2)
        create(:certification, :first, user_id: user.id)
        expect(user.remaining_trainings.ids).to eq([training.id])
      end

    end

    context '#return_program_status' do

      it 'should return status 0' do
        user = create(:user, :regular_user)
        create(:space)
        expect(user.return_program_status).to eq(0)
      end

      it 'should return status 1' do
        user = create(:user, :regular_user_with_certifications)
        expect(user.return_program_status).to eq(1)
      end

      it 'should return status 2' do
        user = create(:user, :regular_user_with_certifications)
        Program.create(user_id: user.id, program_type: Program::VOLUNTEER)
        expect(user.return_program_status).to eq(2)
      end

      it 'should return status 2' do
        volunteer = create(:user, :volunteer)
        create(:certification, :'3d_printing', user_id: volunteer.id)
        create(:certification, :basic_training, user_id: volunteer.id)
        expect(volunteer.return_program_status).to eq(2)
      end

      it 'should return status 3' do
        user = create(:user, :regular_user_with_certifications)
        Program.create(user_id: user.id, program_type: Program::DEV_PROGRAM)
        expect(user.return_program_status).to eq(3)
      end

      it 'should return status 4' do
        volunteer = create(:user, :volunteer_with_dev_program)
        create(:certification, :'3d_printing', user_id: volunteer.id)
        create(:certification, :basic_training, user_id: volunteer.id)
        expect(volunteer.return_program_status).to eq(4)
      end

      it 'should return status 4' do
        user = create(:user, :regular_user_with_certifications)
        Program.create(user_id: user.id, program_type: Program::VOLUNTEER)
        Program.create(user_id: user.id, program_type: Program::DEV_PROGRAM)
        expect(user.return_program_status).to eq(4)
      end

    end

    context '#has_required_badges?' do

      before :each do
        create(:badge_template, :'3d_printing')
        create(:badge_template, :laser_cutting)
        create(:badge_template, :arduino)
      end

      it 'should be false' do
        user = create(:user, :regular_user)
        create(:badge_requirement, :'3d_printing')
        expect(user.has_required_badges?(BadgeRequirement.all)).to be_falsey
      end

      it 'should be true' do
        user = create(:user, :regular_user)
        create(:badge, :'3d_printing', user_id: user.id)
        create(:badge_requirement, :'3d_printing')
        expect(user.has_required_badges?(BadgeRequirement.all)).to be_truthy
      end

      it 'should be true' do
        user = create(:user, :regular_user)
        create(:badge, :'3d_printing', user_id: user.id)
        create(:badge_requirement, :'3d_printing')
        create(:badge, :laser_cutting, user_id: user.id)
        create(:badge_requirement, :laser_cutting)
        create(:badge, :arduino, user_id: user.id)
        expect(user.has_required_badges?(BadgeRequirement.all)).to be_truthy
      end

    end

  end

end
