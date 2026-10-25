require "rails_helper"

RSpec.describe TrainingSession, type: :model do
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
      it "dependent destroy: should destroy certifications if destroyed" do
        training_session = create(:training_session_with_certifications)
        expect { training_session.destroy }.to change {
          Certification.count
        }.by(-training_session.certifications.count)
      end
      it "dependent destroy: should destroy exams if destroyed" do
        training_session = create(:training_session_with_exams)
        expect { training_session.destroy }.to change { Exam.count }.by(
          -training_session.exams.count
        )
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
      expect(ts.errors[:string]).to include("user must be staff")
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
end
