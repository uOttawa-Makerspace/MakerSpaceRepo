require "rails_helper"
include BCrypt
include ActiveModel::Serialization

RSpec.describe User, type: :model do

  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:space).without_validating_presence }
    end
  end

  describe "validation" do
  end

  describe "scopes" do
    let!(:regular_users) { create_list(:user, 2, :regular_user) }
    let!(:admin_user) { create(:user, :admin) }
    let!(:staff_user) { create(:user, :staff) }
    let!(:volunteer_user) { create(:user, :volunteer_with_volunteer_program) }
    let!(:old_regular_users) { create_list(:user, 4, :regular_user, created_at: 1.month.ago) }
    let!(:student_users) { create_list(:user, 5, :student) }
    let!(:ancient_users) { create_list(:user, 2, :regular_user, created_at: 3.years.ago) }

    context "#created_at_month" do
      it "should return 12" do
        expect(User.created_at_month(Date.today.month).count).to eq(12)
      end
    end

    context "#not_created_this_year" do
      it "should return 2" do
        if Time.new.month == 1
          expect(User.not_created_this_year.count).to eq(6)
        else
          expect(User.not_created_this_year.count).to eq(2)
        end
      end
    end

    context "#created_this_year" do
      it "should return 14" do
        if Time.new.month == 1
          expect(User.created_this_year.count).to eq(10)
        else
          expect(User.created_this_year.count).to eq(14)
        end
      end
    end

    context "#students" do
      it "should return 5" do
        expect(User.students.count).to eq(5)
      end
    end

    context "#no_waiver_users" do
      it "should return nothing" do
        expect(User.no_waiver_users.count).to eq(0)
      end
    end

    context "#between_dates_picked" do
      it "should return one" do
        start_date = 2.months.ago
        end_date = 1.day.ago
        expect(User.between_dates_picked(start_date, end_date).count).to eq(4)
      end

      it "should return none" do
        start_date = 2.years.ago
        end_date = 1.year.ago
        expect(User.between_dates_picked(start_date, end_date).count).to eq(0)
      end
    end

    context "#active" do
      it "should return all active users" do
        expect(User.active.count).to eq(User.all.count)
      end

      it "should exclude inactive user" do
        create(:user, :admin, active: false)
        expect(User.active.count).to eq(User.all.count - 1)
      end
    end

    context "#unknown_identity" do
      it "should return 0 users" do
        expect(User.unknown_identity.count).to eq(0)
      end

      it "should return 1 user" do
        create(:user, :admin, identity: "unknown")
        expect(User.unknown_identity.count).to eq(1)
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
        expect(user.display_avatar).to eq("default-avatar.png")
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
      it "should return 0 hours for unapproved hours" do
        volunteer_hour = create(:volunteer_hour, :not_approved1)
        expect(volunteer_hour.user.get_total_hours).to eq(0)
      end

      it "should return 10 hours for approved hours" do
        volunteer_hour = create(:volunteer_hour, :approved1)
        expect(volunteer_hour.user.get_total_hours).to eq(10)
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
        user = create(:user, :regular_user)
        volunteer_task = create(:volunteer_task)
        create(:volunteer_task_join, :first, user: user, volunteer_task: volunteer_task)
        expect(
          user.get_volunteer_tasks_from_volunteer_joins.first.id
        ).to eq(volunteer_task.id)
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
end