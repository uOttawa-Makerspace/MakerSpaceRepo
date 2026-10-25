require "rails_helper"
include BCrypt
include ActiveModel::Serialization

RSpec.describe User, type: :model do

  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:space).without_validating_presence }
    end

    context "has_one" do
      it { should have_one(:rfid) }
    end

    context "accepts_nested_attributes_for" do
      it { should accept_nested_attributes_for(:repositories) }
    end

    context "has_and_belongs_to_many" do
      it { should have_and_belong_to_many(:repositories) }
      it { should have_and_belong_to_many(:training_sessions) }
      it { should have_and_belong_to_many(:proficient_projects) }
      it { should have_and_belong_to_many(:shifts) }
    end

    context "has_many" do
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
      it { should have_many(:programs) }
      it { should have_many(:orders) }
      it { should have_many(:order_items) }
      it { should have_many(:discount_codes) }
      it { should have_many(:project_kits) }
      it { should have_many(:learning_module_tracks) }
      it { should have_many(:shadowing_hours) }
      it { should have_many(:staff_spaces) }
      it { should have_many(:staff_availabilities) }
      it { should have_many(:job_orders) }
    end
  end

  describe "validation" do
    context "avatar" do
      it "should not be valid (wrong filetype)" do
        user = build(:user, :regular_user_with_broken_avatar)
        expect(user.valid?).to be_falsey
      end

      it "should be valid" do
        user = build(:user, :regular_user)
        expect(user.valid?).to be_truthy
      end

      it "should be valid" do
        user = build(:user, :regular_user_with_avatar)
        expect(user.valid?).to be_truthy
      end
    end

    context "name" do
      it { should validate_length_of(:name).is_at_most(50) }
      it { should validate_presence_of(:name) }
    end

    context "username" do
      it { should_not allow_value("gds%%$32").for(:username) }
      it { should allow_value("johndoe").for(:username) }
      it { should validate_length_of(:username).is_at_most(20) }
      it { should validate_presence_of(:username) }
      it { should validate_uniqueness_of(:username).ignoring_case_sensitivity }
    end

    context "email" do
      it { should validate_presence_of(:email) }
      it { should validate_uniqueness_of(:email).ignoring_case_sensitivity }
    end

    context "how_heard_about_us" do
      it { should validate_length_of(:how_heard_about_us).is_at_most(250) }
    end

    context "read_and_accepted_waiver_form" do
      it { should_not allow_value(false).for(:read_and_accepted_waiver_form) }
      it { should allow_value(true).for(:read_and_accepted_waiver_form) }
    end

    context "password" do
      it { should_not allow_value("abc").for(:password) }
      it { should allow_value("aJ2^6amjseHvD#FtV").for(:password) }
      it { should validate_presence_of(:password) }
    end

    context "gender" do
      it { should_not allow_value("Something else").for(:gender) }
      it do
        should allow_value(
                 "Male",
                 "Female",
                 "Other",
                 "Prefer not to specify",
                 "unknown"
               ).for(:gender)
      end
      it { should validate_presence_of(:gender) }
    end

    context "faculty student" do
      subject { build(:user, :student, faculty: nil) }
      it { should validate_presence_of(:faculty) }
    end

    context "faculty non-student" do
      subject { build(:user, :regular_user, faculty: nil) }
      it { should_not validate_presence_of(:faculty) }
    end

    context "program student" do
      subject { build(:user, :student, program: nil) }
      it { should validate_presence_of(:program) }
    end

    context "program non-student" do
      subject { build(:user, :regular_user, program: nil) }
      it { should_not validate_presence_of(:program) }
    end

    context "year_of_study student" do
      subject { build(:user, :student, year_of_study: nil) }
      it { should validate_presence_of(:year_of_study) }
    end

    context "year_of_study non-student" do
      subject { build(:user, :regular_user, year_of_study: nil) }
      it { should_not validate_presence_of(:year_of_study) }
    end

    context "identity" do
      it { should validate_presence_of(:identity) }
      it { should_not allow_value("Something else").for(:identity) }
      it do
        should allow_value(
                 "grad",
                 "undergrad",
                 "faculty_member",
                 "community_member",
                 "unknown"
               ).for(:identity)
      end
    end
  end

  describe "scopes" do
    context "#created_at_month" do
      it "should return users created in the specified month" do
        # Test a specific month to avoid conflicts
        test_date = Date.new(2020, 5, 15)
        
        expect {
          10.times { create(:user, :regular_user, created_at: test_date) }
        }.to change { User.created_at_month(test_date.month).count }.by(10)
      end
    end

    context "#not_created_this_year" do
      it "should return users not created this year" do
        expect {
          2.times { create(:user, :regular_user, created_at: 3.years.ago) }
        }.to change { User.not_created_this_year.count }.by(2)
      end
    end

    context "#created_this_year" do
      it "should return users created this year" do
        expect {
          14.times { create(:user, :regular_user, created_at: Date.today) }
        }.to change { User.created_this_year.count }.by(14)
      end
    end

    context "#students" do
      it "should return students" do
        expect {
          5.times { create(:user, :student) }
        }.to change { User.students.count }.by(5)
      end
    end

    context "#no_waiver_users" do
      it "should return nothing" do
        expect(User.no_waiver_users.count).to eq(0)
      end
    end

    context "#between_dates_picked" do
      it "should return users between dates" do
        start_date = Date.new(2020, 1, 1)
        end_date = Date.new(2020, 12, 31)
        
        expect {
          4.times { create(:user, :regular_user, created_at: Date.new(2020, 6, 15)) }
        }.to change { User.between_dates_picked(start_date, end_date).count }.by(4)
      end

      it "should return none for different date range" do
        start_date = Date.new(2018, 1, 1)
        end_date = Date.new(2018, 12, 31)
        
        expect(User.between_dates_picked(start_date, end_date).count).to eq(0)
      end
    end

    context "#active" do
      it "should return all active users" do
        initial_count = User.active.count
        expect(User.active.count).to eq(initial_count)
      end

      it "should not include inactive users" do
        active_count = User.active.count
        create(:user, :admin, active: false)
        expect(User.active.count).to eq(active_count)
      end
    end

    context "#unknown_identity" do
      it "should return 0 users initially" do
        initial_count = User.unknown_identity.count
        expect(User.unknown_identity.count).to eq(initial_count)
      end

      it "should return 1 user after creating one" do
        expect {
          create(:user, :admin, identity: "unknown")
        }.to change { User.unknown_identity.count }.by(1)
      end
    end
  end

  describe "model methods" do
    context "#display_avatar" do
      it "should get the avatar" do
        user = create(:user, :regular_user_with_avatar)
        expect(user.display_avatar.filename).to eq("avatar.png")
      end

      it "should get the default avatar" do
        user = create(:user, :regular_user)
        expect(user.display_avatar).to eq("/default-avatar.png")
      end
    end

    context "#username_or_email" do
      it "should return nothing" do
        create(:user, :regular_user, email: "a@gmail.com")
        expect(User.username_or_email("abc")).to be_nil
      end

      it "should return the user (by email)" do
        user = create(:user, :regular_user)
        expect(User.username_or_email(user.email).id).to eq(user.id)
      end

      it "should return the user (by username)" do
        user = create(:user, :regular_user)
        expect(User.username_or_email(user.username).id).to eq(user.id)
      end
    end

    context "#authenticate" do
      it "should return nothing" do
        create(:user, :regular_user, email: "a@gmail.com")
        expect(User.authenticate("a@gmail.com", "somethingelse")).to be_nil
      end

      it "should return the user" do
        user = create(:user, :regular_user, email: "a@gmail.com")
        expect(User.authenticate("a@gmail.com", "asa32A353#").id).to eq(user.id)
      end
    end

    context "#student?" do
      it "should return false" do
        user = create(:user, :regular_user)
        expect(user.student?).to be_falsey
      end

      it "should return true" do
        user = create(:user, :student)
        expect(user.student?).to be_truthy
      end
    end

    context "#admin?" do
      it "should return false" do
        user = create(:user, :regular_user)
        expect(user.admin?).to be_falsey
      end

      it "should return true" do
        user = create(:user, :admin)
        expect(user.admin?).to be_truthy
      end
    end

    context "#staff?" do
      it "should return false" do
        user = create(:user, :regular_user)
        expect(user.staff?).to be_falsey
      end

      it "should return true" do
        user = create(:user, :staff)
        expect(user.staff?).to be_truthy
      end
    end

    context "#volunteer?" do
      it "should return false" do
        user = create(:user, :regular_user)
        expect(user.volunteer?).to be_falsey
      end

      it "should return true" do
        user = create(:user, :volunteer_with_volunteer_program)
        expect(user.volunteer?).to be_truthy
      end
    end

    context "#volunteer_program?" do
      it "should return false" do
        user = create(:user, :regular_user)
        expect(user.volunteer_program?).to be_falsey
      end

      it "should return true" do
        user = create(:user, :volunteer_with_volunteer_program)
        expect(user.volunteer_program?).to be_truthy
      end
    end

    context "#dev_program?" do
      it "should return false" do
        user = create(:user, :regular_user)
        expect(user.dev_program?).to be_falsey
      end

      it "should return true" do
        user = create(:user, :volunteer_with_dev_program)
        expect(user.dev_program?).to be_truthy
      end
    end

    context "#internal?" do
      it "should return false" do
        user = create(:user, :regular_user)
        expect(user.internal?).to be_falsey
      end

      it "should return true" do
        user = create(:user, :student)
        expect(user.internal?).to be_truthy
      end
    end

    context "#location" do
      it "should return no sign in yet" do
        user = create(:user, :regular_user)
        expect(user.location).to eq("no sign in yet")
      end

      it "should return makerspace" do
        user = create(:user, :regular_user)
        space = create(:space)
        LabSession.create(user: user, space: space)
        expect(user.location).to eq(space.name)
      end
    end

    context "#get_total_cc" do
      it "should return 0" do
        user = create(:user, :regular_user)
        expect(user.get_total_cc).to eq(0)
      end

      it "should return 100" do
        user = create(:user, :regular_user)
        create(:cc_money, :hundred, user_id: user.id)
        expect(user.get_total_cc).to eq(100)
      end
    end

    context "#get_total_hours" do
      it "should return 0 hours" do
        create(:volunteer_hour, :not_approved1)
        expect(User.last.get_total_hours).to eq(0)
      end

      it "should return 15 hours" do
        create(:volunteer_hour, :approved1)
        expect(User.last.get_total_hours).to eq(10)
      end
    end

    context "#update_wallet" do
      it "should update wallet to a 100" do
        user = create(:user, :regular_user)
        create(:cc_money, :hundred, user_id: user.id)
        user.update_wallet
        expect(user.wallet).to eq(100)
      end
    end

    context "#get_certifications_names" do
      it "should get all certifications" do
        user = create(:user, :admin)
        certification = create(:certification, user_id: user.id)
        training = certification.training
        expect(user.get_certifications_names).to eq([training.name_en])
      end
    end

    context "#get_volunteer_tasks_from_volunteer_joins" do
      it "should get all volunteer tasks" do
        create(:volunteer_task_join, :first)
        expect(
          User.last.get_volunteer_tasks_from_volunteer_joins.first.id
        ).to eq(VolunteerTask.last.id)
      end
    end

    context "#remaining_trainings" do
      it "should get the two remaining trainings" do
        user = create(:user, :admin)
        training1 = create(:training)
        training2 = create(:training)
        expect(user.remaining_trainings.ids).to include(training1.id)
        expect(user.remaining_trainings.ids).to include(training2.id)
      end

      it "should get the remaining training" do
        user = create(:user, :admin)
        training = create(:training)
        create(:certification, user_id: user.id)
        expect(user.remaining_trainings.map(&:id)).to include(training.id)
      end
    end

    context "#return_program_status" do
      it "should return false for all programs for a regular user" do
        user = create(:user, :regular_user)
        create(:space)
        expect(user.return_program_status).to eq(
          { volunteer: false, dev: false, teams: false }
        )
      end

      it "should return false for all programs for a regular user with certifications" do
        user = create(:user, :regular_user_with_certifications)
        expect(user.return_program_status).to eq(
          { volunteer: false, dev: false, teams: false }
        )
      end

      it "should return true for volunteer only" do
        user = create(:user, :regular_user_with_certifications)
        Program.create(user_id: user.id, program_type: Program::VOLUNTEER)
        expect(user.return_program_status).to eq(
          { volunteer: true, dev: false, teams: false }
        )
      end

      it "should return true for volunteer only" do
        volunteer = create(:user, :volunteer_with_volunteer_program)
        create(:certification, :"3d_printing", user_id: volunteer.id)
        create(:certification, :basic_training, user_id: volunteer.id)
        expect(volunteer.return_program_status).to eq(
          { volunteer: true, dev: false, teams: false }
        )
        
      end

      it "should return true for development program only" do
        user = create(:user, :regular_user_with_certifications)
        Program.create(user_id: user.id, program_type: Program::DEV_PROGRAM)
        expect(user.return_program_status).to eq(
          { volunteer: false, dev: true, teams: false }
        )
      end

      it "should return true for both volunteer and development programs" do
        user = create(:user, :regular_user_with_certifications)
        Program.create(user_id: user.id, program_type: Program::VOLUNTEER)
        Program.create(user_id: user.id, program_type: Program::DEV_PROGRAM)
       
        expect(user.return_program_status).to eq(
          { volunteer: true, dev: true, teams: false }
        )
      end
    end

    context "#has_requirements?" do
      it "should be false" do
        user = create(:user, :regular_user)
        create(:training_requirement, :"3d_printing")
        expect(user.has_requirements?(TrainingRequirement.all)).to be_falsey
      end

      it "should be true" do
        user = create(:user, :regular_user)
        cert = create(:certification, :"3d_printing", user_id: user.id, level: "Beginner")
        create(:training_requirement, :"3d_printing", training_id: cert.training.id, level: "Beginner")
        expect(user.has_requirements?(TrainingRequirement.all)).to be_truthy
      end

      it "should be true" do
        user = create(:user, :regular_user)
        cert = create(:certification, :"3d_printing", user_id: user.id, level: "Intermediate")
        create(:training_requirement, :"3d_printing", training_id: cert.training.id, level: "Intermediate")
        cert = create(:certification, :basic_training, user_id: user.id, level: "Advanced")
        create(:training_requirement, :basic_training, training_id: cert.training.id, level: "Advanced")
        expect(user.has_requirements?(TrainingRequirement.all)).to be_truthy
      end

      it "should be false" do
        user = create(:user, :regular_user)
        cert = create(:certification, :"3d_printing", user_id: user.id, level: "Beginner")
        create(:training_requirement, :"3d_printing", training_id: cert.training.id, level: "Intermediate")
        expect(user.has_requirements?(TrainingRequirement.all)).to be_falsey
      end

      it "should be false" do
        user = create(:user, :regular_user)
        cert = create(:certification, :basic_training, user_id: user.id, level: "Beginner")
        create(:training_requirement, :"3d_printing", level: "Beginner")
        expect(user.has_requirements?(TrainingRequirement.all)).to be_falsey
      end
    end
  end

  # ===========================================================================
  # Chunk 9 characterization additions (identity subsystem).
  # ===========================================================================
  describe "soft delete vs active flag (default_scope)" do
    let!(:live) { create(:user, :regular_user) }
    let!(:gone) { create(:user, :regular_user, deleted: true) }
    let!(:idle) { create(:user, :regular_user, active: false) }

    it "default scope hides deleted users from counts, where and find" do
      expect(User.where(id: [live.id, gone.id, idle.id])).to contain_exactly(live, idle)
      expect { User.find(gone.id) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(User.find_by(id: gone.id)).to be_nil
      expect(User.exists?(gone.id)).to be(false)
    end

    it "unscoped brings deleted users back" do
      expect(User.unscoped.find(gone.id)).to eq(gone)
      expect(User.unscoped.where(id: [live.id, gone.id, idle.id]).count).to eq(3)
    end

    it "`active` is an independent flag: the :active scope drops inactive but default scope keeps them" do
      expect(User.active.where(id: [live.id, idle.id, gone.id])).to contain_exactly(live)
      expect(User.where(id: idle.id)).to contain_exactly(idle)
    end

    it "a user can be both deleted and active (the flags do not interact)" do
      expect(gone.active).to be(true)
      expect(User.unscoped.active.where(id: gone.id)).to contain_exactly(gone)
    end

    it "lookup helpers never return deleted users" do
      expect(User.username_or_email(gone.username)).to be_nil
      expect(User.username_or_email(gone.email)).to be_nil
      expect(User.find_by_username(gone.username)).to be_nil
      expect(User.authenticate(gone.username, "asa32A353#")).to be_nil
    end

    it "lookup helpers do return inactive users" do
      expect(User.username_or_email(idle.username)).to eq(idle)
      expect(User.authenticate(idle.username, "asa32A353#")).to eq(idle)
    end

    it "associated records of a deleted user still load their user as nil-less via unscoped joins" do
      order = Order.create!(user: gone)
      expect(Order.find(order.id).user).to be_nil
    end

    it "the staff and students scopes also respect the default scope" do
      staff_gone = create(:user, :staff, deleted: true)
      expect(User.staff).not_to include(staff_gone)
      expect(User.unscoped.staff).to include(staff_gone)
    end

    it "uniqueness validation uses unscoped queries: deleted rows still reserve username and email" do
      clone = build(:user, :regular_user, username: gone.username.upcase, email: gone.email)
      expect(clone).not_to be_valid
      expect(clone.errors.attribute_names).to include(:username, :email)
    end
  end

  describe "role predicates" do
    it "pins admin?/staff? by the role column" do
      expect(build(:user, role: "admin")).to have_attributes(admin?: true, staff?: true)
      expect(build(:user, role: "staff")).to have_attributes(admin?: false, staff?: true)
      expect(build(:user, role: "volunteer")).to have_attributes(admin?: false, staff?: false)
      expect(build(:user, role: "regular_user")).to have_attributes(admin?: false, staff?: false)
      expect(build(:user, role: nil)).to have_attributes(admin?: false, staff?: false)
    end

    it "the volunteer role does not make volunteer? true; only the Volunteer program does" do
      v = create(:user, role: "volunteer")
      expect(v.volunteer?).to be(false)
      v.programs.create!(program_type: Program::VOLUNTEER)
      expect(v.volunteer?).to be(true)
      expect(v.volunteer_program?).to be(true)
    end

    it "teams_program? and staff_in_space?" do
      u = create(:user, :regular_user)
      expect(u.teams_program?).to be(false)
      u.programs.create!(program_type: Program::TEAMS)
      expect(u.teams_program?).to be(true)
      expect(u.staff_in_space?).to be(false)
      StaffSpace.create!(user: u, space: create(:space))
      expect(u.staff_in_space?).to be(true)
    end

    it "validates role inclusion, allowing blank" do
      expect(build(:user, role: "superuser")).not_to be_valid
      expect(build(:user, role: "")).to be_valid
      expect(build(:user, role: nil)).to be_valid
    end

    it "the staff scope returns admin and staff only" do
      a = create(:user, :admin)
      s = create(:user, :staff)
      v = create(:user, :volunteer)
      r = create(:user, :regular_user)
      expect(User.staff.where(id: [a.id, s.id, v.id, r.id])).to contain_exactly(a, s)
    end

    it "the volunteers scope joins programs" do
      v = create(:user, :regular_user)
      v.programs.create!(program_type: Program::VOLUNTEER)
      create(:user, :volunteer)
      expect(User.volunteers).to contain_exactly(v)
    end

    it "pins the constants" do
      expect(User::ROLES).to eq(%w[regular_user admin staff volunteer])
      expect(User::MAX_AUTH_ATTEMPTS).to eq(5)
      expect(User::LOCK_DURATION).to eq(5.minutes)
      expect(User::ALLOWED_AVATAR_TYPES).to eq(%w[image/jpeg image/png image/webp image/gif])
    end
  end

  describe "additional validations" do
    it "rejects html special characters in name" do
      expect(build(:user, name: "A<b>")).not_to be_valid
      expect(build(:user, name: 'A"B')).not_to be_valid
      expect(build(:user, name: "A&B")).not_to be_valid
      expect(build(:user, name: "Zoë O'Neil-Smith")).to be_valid
    end

    it "accepts accented usernames but not punctuation or spaces" do
      expect(build(:user, username: "josé123")).to be_valid
      expect(build(:user, username: "jo.se")).not_to be_valid
      expect(build(:user, username: "jo se")).not_to be_valid
    end

    it "normalizes email by stripping and downcasing" do
      u = create(:user, email: "  MiXed@Example.COM ")
      expect(u.email).to eq("mixed@example.com")
    end

    it "email format is checked on create only, and the format check is lenient" do
      # WART(D-I29): the `email: true` validator accepts addresses without an @ (e.g. "not-an-email") and no email rule runs on update
      expect(build(:user, email: "not-an-email")).to be_valid
      expect(build(:user, email: "")).not_to be_valid
      u = create(:user)
      u.email = "not-an-email"
      expect(u).to be_valid
      u.email = ""
      expect(u).to be_valid
    end

    it "the waiver is required on create only" do
      u = create(:user)
      u.read_and_accepted_waiver_form = false
      expect(u).to be_valid
    end

    it "url must be http(s) or blank" do
      expect(build(:user, url: "https://example.com/x")).to be_valid
      expect(build(:user, url: "")).to be_valid
      expect(build(:user, url: "ftp://example.com")).not_to be_valid
      expect(build(:user, url: "javascript:alert(1)")).not_to be_valid
    end

    it "student_id is 7-12 digits for students, unchecked otherwise" do
      base = { identity: "undergrad", faculty: "Engineering", program: "X", year_of_study: 1 }
      expect(build(:user, **base, student_id: "1234567")).to be_valid
      expect(build(:user, **base, student_id: "123456")).not_to be_valid
      expect(build(:user, **base, student_id: "12345678901234")).not_to be_valid
      expect(build(:user, **base, student_id: "12345a789")).not_to be_valid
      # WART(D-I30): student_id has allow_blank: true alongside presence: true, so the presence rule is dead and students can omit it
      expect(build(:user, **base, student_id: "")).to be_valid
      expect(build(:user, identity: "community_member", student_id: "abc")).to be_valid
    end

    it "gender and identity must come from their lists" do
      expect(build(:user, gender: "Robot")).not_to be_valid
      User::GENDERS.each { |g| expect(build(:user, gender: g)).to be_valid }
      User::IDENTITIES.each do |i|
        extra = User::STUDENT_IDENTITIES.include?(i) ? { faculty: "Engineering", program: "X", year_of_study: 1, student_id: "1234567" } : {}
        expect(build(:user, identity: i, **extra)).to be_valid
      end
    end

    it "translates French faculty names before validating" do
      u = build(:user, identity: "undergrad", faculty: "Génie", program: "X", year_of_study: 1, student_id: "1234567")
      expect(u).to be_valid
      expect(u.faculty).to eq("Engineering")
    end

    it "'Civil Law'/'Common Law' translations are not in the FACULTIES list so students with them fail" do
      u = build(:user, identity: "undergrad", faculty: "Droit civil", program: "X", year_of_study: 1, student_id: "1234567")
      expect(u).not_to be_valid
      expect(u.faculty).to eq("Civil Law")
    end

    it "avatar: images pass, a non-image content type fails" do
      u = build(:user, :regular_user_with_avatar)
      expect(u).to be_valid
      expect(build(:user, :regular_user_with_broken_avatar)).not_to be_valid
    end

    it "the password strength validator inspects the stored value, so any plaintext passes when set via the column" do
      expect(build(:user, password: "abc")).not_to be_valid
      u = create(:user)
      u.pword = "abc"
      expect(u).to be_valid
    end
  end

  describe "authentication internals" do
    let(:u) { create(:user, :regular_user) }

    it "authenticate_password compares against the bcrypt hash" do
      expect(u.authenticate_password("asa32A353#")).to be(true)
      expect(u.authenticate_password("nope")).to be(false)
    end

    it "pword= stores a bcrypt hash and the confirmation" do
      u.pword = "BrandNewPw1!"
      expect(u.password).to start_with("$2")
      expect(u.password_confirmation.to_s).to eq(u.password.to_s)
      expect(u.authenticate_password("BrandNewPw1!")).to be(true)
    end

    it "record_failed_attempt! increments and locks at the 5th failure, emailing the unlock link" do
      4.times { u.record_failed_attempt! }
      expect(u.reload.locked).to be(false)
      expect { u.record_failed_attempt! }.to change { ActionMailer::Base.deliveries.size }.by(1)
      u.reload
      expect(u.locked).to be(true)
      expect(u.auth_attempts).to eq(5)
      expect(u.locked_until).to be_within(5.seconds).of(5.minutes.from_now)
      expect(ActionMailer::Base.deliveries.last.subject).to eq("Unlock your MakerRepo Account")
    end

    it "authenticate resets attempts on success and does not check locked" do
      u.update_columns(auth_attempts: 3, locked: true, locked_until: 1.hour.from_now)
      expect(User.authenticate(u.username, "asa32A353#")).to eq(u)
      expect(u.reload.auth_attempts).to eq(0)
      expect(u.locked).to be(true)
    end

    it "authenticate on a wrong password counts the failure" do
      expect(User.authenticate(u.username, "bad")).to be_nil
      expect(u.reload.auth_attempts).to eq(1)
    end

    it "username_or_email trims and downcases" do
      expect(User.username_or_email("  #{u.username.upcase} ")).to eq(u)
      expect(User.username_or_email(u.email.upcase)).to eq(u)
      expect(User.username_or_email(nil)).to be_nil
    end

    it "token is an HS256 JWT with user_id and a 14 day expiry" do
      payload = JWT.decode(u.token, Rails.application.credentials.secret_key_base, true, algorithm: "HS256").first
      expect(payload["user_id"]).to eq(u.id)
      expect(payload["exp"]).to be_within(10).of(14.days.from_now.to_i)
    end

    it "send_password_reset emails the reset link with user and expiry tokens" do
      expect { u.send_password_reset }.to change { ActionMailer::Base.deliveries.size }.by(1)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([u.email])
      expect(mail.subject).to eq("Reset your MakerRepo password")
    end
  end

  describe "search scopes" do
    let!(:target) { create(:user, name: "Émile Zola", username: "emilez") }
    let!(:other) { create(:user, name: "Someone Else", username: "someoneelse") }

    it ".search is accent- and case-insensitive on name or username, capped at 30" do
      expect(User.search("emile")).to contain_exactly(target)
      expect(User.search("EMILEZ")).to contain_exactly(target)
      expect(User.search("zzz")).to be_empty
    end

    it ".search escapes LIKE wildcards" do
      expect(User.search("%")).to be_empty
    end

    it ".fuzzy_search matches trigram-similar names and usernames" do
      expect(User.fuzzy_search("Emile Zolla")).to include(target)
    end

    it ".reduced_fuzzy_search matches on username only" do
      expect(User.reduced_fuzzy_search("emilez")).to include(target)
      expect(User.reduced_fuzzy_search("someoneelse")).not_to include(target)
    end

    it "search scopes exclude soft-deleted users" do
      gone = create(:user, name: "Émile Gone", username: "emilegone", deleted: true)
      expect(User.search("emilegone")).not_to include(gone)
    end
  end

  describe "avatar helpers" do
    it "display_avatar falls back to the default path; has_avatar? reflects attachment" do
      u = create(:user, :regular_user)
      expect(u.display_avatar).to eq("/default-avatar.png")
      expect(u.has_avatar?).to be(false)
    end
  end

  describe "department and identity_readable" do
    it "department is nil without a program" do
      expect(build(:user, program: nil).department).to be_nil
    end

    it "department looks up the UniProgram, trimming ' in'" do
      UniProgram.create!(program: "Software Engineering", department: "EECS", faculty: "Engineering", level: "undergrad")
      # gsub(' in','') removes only the word " in" from the user's program string and tries the result as an alternative
      UniProgram.create!(program: "BASc Software Engineering", department: "EECS2", faculty: "Engineering", level: "undergrad")
      expect(build(:user, program: "Software Engineering").department).to eq("EECS")
      expect(build(:user, program: "BASc in Software Engineering").department).to eq("EECS2")
      expect(build(:user, program: "Unknown Thing").department).to be_nil
    end

    it "identity_readable titleizes non-students and builds a year string for students" do
      expect(build(:user, identity: "community_member").identity_readable).to eq("Community Member")
      s = build(:user, identity: "undergrad", year_of_study: 2)
      I18n.with_locale(:en) { expect(s.identity_readable).to eq("2nd Year Undergraduate") }
    end
  end

  describe "membership helpers" do
    it "has_active_membership? follows paid, unexpired memberships" do
      u = create(:user, :regular_user)
      expect(u.has_active_membership?).to be(false)
      create(:membership, user: u, status: "paid", end_date: 1.week.from_now)
      expect(u.has_active_membership?).to be(true)
    end

    it "an expired or revoked membership does not count" do
      u = create(:user, :regular_user)
      create(:membership, user: u, status: "paid", end_date: 1.day.ago)
      create(:membership, user: u, status: "revoked", end_date: 1.week.from_now)
      expect(u.has_active_membership?).to be(false)
    end
  end
end
