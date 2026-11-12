require "rails_helper"

RSpec.describe TrainingSession, type: :model do
  describe "editing once certifications are awarded" do
    let(:open_session) { create(:training_session, level: "Beginner") }
    let(:awarded_session) { create(:training_session_with_certifications, level: "Beginner").reload }
    let(:other_training) { create(:training) }

    def edit(session, attributes)
      session.assign_attributes(attributes)
      session.save(context: :session_edit)
    end

    it "does not apply the lock to writes that are not edits of the session" do
      new_trainer = create(:user, :staff)
      expect(awarded_session.update(user: new_trainer)).to be(true)
      expect(awarded_session.reload.user).to eq(new_trainer)
    end

    it "is editable while no certification was awarded" do
      expect(open_session).to be_editable
      expect(edit(open_session, level: "Advanced", training: other_training)).to be(true)
      expect(open_session.reload.level).to eq("Advanced")
    end

    it "is not editable once it awarded a certification, even a demoted one" do
      expect(awarded_session).not_to be_editable
      awarded_session.certifications.each { |cert| cert.update!(active: false) }
      expect(awarded_session.reload).not_to be_editable
    end

    it "refuses a new training, level or instructor and keeps the stored values" do
      before = awarded_session.attributes.slice("training_id", "level", "user_id")
      expect(edit(awarded_session, level: "Advanced")).to be(false)
      expect(awarded_session.errors.full_messages.to_sentence).to include("cannot be changed once the session has awarded")
      expect(edit(awarded_session.reload, training: other_training)).to be(false)
      expect(edit(awarded_session.reload, user: create(:user, :staff))).to be(false)
      expect(awarded_session.reload.attributes.slice("training_id", "level", "user_id")).to eq(before)
      expect(awarded_session.certifications.map(&:level).uniq).to eq(["Beginner"])
    end

    it "still accepts the other fields" do
      expect(edit(awarded_session, course: "Some course")).to be(true)
      expect(awarded_session.reload.course).to eq("Some course")
    end

    it "reports whether an attribute set touches a locked field" do
      expect(awarded_session.locked_change?("level" => "Advanced")).to be(true)
      expect(awarded_session.locked_change?("level" => "Beginner")).to be(false)
      expect(awarded_session.locked_change?(course: "x")).to be(false)
      expect(open_session.locked_change?("level" => "Advanced")).to be(false)
    end
  end

  describe "Association" do
    context "has_and_belong_to_many" do
      it { should have_and_belong_to_many(:users) }
    end

    context "belongs_to" do
      it do
        expect(TrainingSession.reflect_on_association(:training).macro).to eq(
          :belongs_to
        )
      end
      it do
        expect(TrainingSession.reflect_on_association(:user).macro).to eq(
          :belongs_to
        )
      end
      it do
        expect(TrainingSession.reflect_on_association(:space).macro).to eq(
          :belongs_to
        )
      end
      it do
        expect(
          TrainingSession.reflect_on_association(:course_name).macro
        ).to eq(:belongs_to)
      end
    end

    context "has_many" do
      it { should have_many(:certifications) }
      it { should have_many(:exams) }
      it { should have_many(:awarded_certifications).dependent(:restrict_with_error) }
      it { should have_many(:exams).dependent(:restrict_with_error) }
      let(:deleted_refusal) { "This training session has awarded certifications or has exams, so it cannot be deleted." }

      it "refuses to be deleted while it has certifications, keeping them" do
        training_session = create(:training_session_with_certifications)
        expect { training_session.destroy }.not_to change { [TrainingSession.count, Certification.count] }
        expect(training_session.errors.full_messages).to eq([deleted_refusal])
      end
      it "refuses to be deleted when its only certification is demoted" do
        training_session = create(:training_session)
        cert = create(:certification, training_session: training_session, training: training_session.training)
        cert.update!(active: false)
        expect { training_session.destroy }.not_to change { [TrainingSession.count, Certification.unscoped.count] }
        expect(training_session.errors.full_messages).to eq([deleted_refusal])
      end
      it "refuses to be deleted while it has exams, keeping them" do
        training_session = create(:training_session_with_exams)
        expect { training_session.destroy }.not_to change { [TrainingSession.count, Exam.count] }
        expect(training_session.errors.full_messages).to eq([deleted_refusal])
      end
      it "explains the refusal in French" do
        training_session = create(:training_session_with_exams)
        training_session.destroy
        I18n.with_locale(:fr) do
          expect(training_session.errors.full_messages).to eq(
            ["Cette séance de formation a délivré des certifications ou a des examens, elle ne peut donc pas être supprimée."]
          )
        end
      end
      it "is deleted when it has no certifications or exams" do
        training_session = create(:training_session)
        expect { training_session.destroy }.to change(TrainingSession, :count).by(-1)
      end
    end
  end

  describe "Validations" do
    context "presence and uniqueness" do
      subject { create(:training_session) }
      it do
        should validate_presence_of(:training).with_message(
                 "A training subject is required"
               )
      end
      it do
        should validate_presence_of(:level).with_message("A level is required")
      end
    end
  end

  describe "Methods" do
    before(:each) do
      TrainingSession.destroy_all
      
      @training_session =
        create(:training_session, created_at: DateTime.yesterday.end_of_day)
      3.times { create(:training_session, created_at: DateTime.now.end_of_day) }
    end

    context "#completed?" do
      it "should return false" do
        expect(@training_session.completed?).to eq(false)
      end

      it "should return true" do
        training_session = create(:training_session_with_certifications)
        expect(training_session.completed?).to eq(true)
      end
    end

    context "#levels" do
      it "should return list of levels" do
        levels = %w[Beginner Intermediate Advanced]
        expect(@training_session.levels).to eq(levels)
      end
    end

    context "#return_levels" do
      it "should return list of levels" do
        levels = %w[General Beginner Intermediate Advanced]
        expect(TrainingSession.return_levels).to eq(levels)
      end
    end

    context "#check_course" do
      it "should return course as nil" do
        training_session = build(:training_session, course: "no course")
        training_session.send(:check_course)
        expect(training_session.course).to eq(nil)
      end

      it "should not return course as nil" do
        training_session = build(:training_session, course: "GNG2101")
        training_session.send(:check_course)
        expect(training_session.course).to eq("GNG2101")
      end
    end

    context "#between_dates_picked" do
      it "should return no training sessions" do
        start_date = DateTime.yesterday.beginning_of_day
        end_date = DateTime.yesterday.end_of_day
        expect(
          TrainingSession.between_dates_picked(start_date, end_date).count
        ).to eq(1)
      end

      it "should return one training sessions" do
        start_date = DateTime.yesterday.beginning_of_day
        end_date = DateTime.tomorrow.end_of_day
        expect(
          TrainingSession.between_dates_picked(start_date, end_date).count
        ).to eq(4)
      end
    end

  end

  describe "Chunk 12: validations and filters" do
    it "requires a staff/admin trainer, training, level and space" do
      ts = TrainingSession.new(user: create(:user, :regular_user), level: "")
      expect(ts).not_to be_valid
      expect(ts.errors[:user]).to include("must be staff")
      expect(ts.errors.full_messages).to include("User must be staff")
      expect(ts.errors[:training]).to include("A training subject is required")
      expect(ts.errors[:level]).to include("A level is required")
      expect(ts.errors[:space]).to be_present
    end

    it "accepts staff and admin trainers" do
      %i[staff admin].each do |role|
        expect(build(:training_session, user: create(:user, role), level: "Beginner")).to be_valid
      end
    end

    it "does not validate the level vocabulary" do
      expect(build(:training_session, level: "Wizard")).to be_valid
    end

    it "by_status completed / not_completed follows the certifications" do
      done = create(:training_session, level: "Beginner")
      open_one = create(:training_session, level: "Beginner")
      create(:certification, training_session: done, training: done.training)
      expect(TrainingSession.by_status("completed")).to eq([done])
      expect(TrainingSession.by_status("not_completed")).to eq([open_one])
    end

    it "filter_by_date_range 30_days excludes older sessions; unknown ranges mean all" do
      old = create(:training_session, level: "Beginner")
      old.update_columns(created_at: 40.days.ago)
      fresh = create(:training_session, level: "Beginner")
      expect(TrainingSession.filter_by_date_range("30_days")).to eq([fresh])
      expect(TrainingSession.filter_by_date_range("all")).to match_array([old, fresh])
    end

    it "orders by updated_at desc by default and filters by trainer and training" do
      a = create(:training_session, level: "Beginner")
      b = create(:training_session, level: "Beginner")
      expect(TrainingSession.all.first).to eq(b)
      expect(TrainingSession.by_trainers(a.user_id)).to eq([a])
      expect(TrainingSession.by_training(b.training_id)).to eq([b])
    end

    it "filter_by_attribute strips the search= prefix and matches the training name" do
      a = create(:training_session, level: "Beginner")
      create(:training_session, level: "Beginner")
      expect(TrainingSession.joins(:training).filter_by_attribute("search=#{a.training.name_en.tr(' ', '+')}")).to eq([a])
    end
  end

  describe "#certify_trainees! and the instructor" do
    let(:instructor) { create(:user, :staff) }
    let(:space) { create(:space) }
    let(:training) { create(:training, spaces: [space]) }
    let(:student) { create(:user, :regular_user) }
    let(:session) { create(:training_session, user: instructor, training: training, space: space, level: "Advanced") }

    it "never certifies the instructor, certifies the other trainees and flags self_skipped" do
      session.users << [instructor, student]
      result = nil
      expect { result = session.certify_trainees! }.to change(Certification, :count).by(1)
      expect(Certification.where(user_id: instructor.id).count).to eq(0)
      expect(Certification.where(user_id: student.id).pluck(:training_session_id, :level)).to eq([[session.id, "Advanced"]])
      expect(result.self_skipped).to be(true)
      expect(result.failed).to be_empty
      expect(result.duplicates).to eq(0)
      expect(result.certified?).to be(true)
    end

    it "applies to an admin instructor too" do
      admin = create(:user, :admin)
      s = create(:training_session, user: admin, training: training, space: space, level: "Beginner")
      s.users << [admin, student]
      result = s.certify_trainees!
      expect(Certification.where(user_id: admin.id).count).to eq(0)
      expect(Certification.where(user_id: student.id).count).to eq(1)
      expect(result.self_skipped).to be(true)
    end

    it "does not flag self_skipped when the instructor is not a trainee" do
      session.users << student
      result = session.certify_trainees!
      expect(result.self_skipped).to be(false)
      expect(Certification.where(user_id: student.id).count).to eq(1)
    end
  end

  describe "#update_roster" do
    let(:trainer) { create(:user, :staff) }
    let(:session) { create(:training_session, user: trainer, level: "Beginner") }
    let(:kept) { create(:user) }
    let(:dropped) { create(:user) }
    let(:added) { create(:user) }

    before { session.users << [kept, dropped] }

    it "saves the fields, adds and removes users by username without duplicates, and links a course name" do
      course = create(:course_name, name: "Intro")
      result = session.update_roster(
        { "level" => "Advanced", "course" => "Intro" },
        added: [added.username, added.username, kept.username], dropped: [dropped.username], by: trainer
      )
      expect(result).to be_saved
      session.reload
      expect([session.level, session.course_name]).to eq(["Advanced", course])
      expect(session.users).to contain_exactly(kept, added)
    end

    it "deactivates the dropped trainee's certification of the session and keeps the row" do
      cert = create(:certification, user: dropped, training_session: session, training: session.training)
      expect(session.update_roster({}, added: [], dropped: [dropped.username], by: trainer)).to be_saved
      expect(Certification.unscoped.find(cert.id)).to have_attributes(active: false, demotion_staff: trainer)
    end

    it "lists the user whose certification could not be deactivated and still applies the rest" do
      create(:certification, user: dropped, training_session: session, training: session.training)
      allow_any_instance_of(Certification).to receive(:deactivate).and_return(false)
      result = session.update_roster({}, added: [added.username], dropped: [dropped.username], by: trainer)
      expect(result).to be_saved
      expect(result.failed_certifications).to eq([dropped])
      expect(session.reload.users).to contain_exactly(kept, added)
    end

    it "writes nothing when the session is invalid" do
      cert = create(:certification, user: dropped, training_session: session, training: session.training)
      result = session.update_roster({ "training_id" => 0 }, added: [added.username], dropped: [dropped.username], by: trainer)
      expect(result).not_to be_saved
      expect(session.errors).not_to be_empty
      expect(session.reload.users).to contain_exactly(kept, dropped)
      expect(Certification.find(cert.id)).to be_active
    end
  end
end
