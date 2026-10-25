require "rails_helper"

RSpec.describe Certification, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:training_session).without_validating_presence }
    end

    context "has_one" do
      it { should have_one(:space) }
      it { should have_one(:training) }
    end
  end

  describe "Validations" do
    context "presence" do
      it do
        should validate_presence_of(:user).with_message("A user is required.")
      end
    end
  end

  describe "Scopes" do
    context "#between_dates_picked" do
      it "should return certifications between dates" do
        create(
          :certification,
          created_at: DateTime.yesterday.end_of_day,
          updated_at: DateTime.yesterday.end_of_day
        )
        create(
          :certification,
          created_at: DateTime.now.end_of_day,
          updated_at: DateTime.now.end_of_day
        )
        create(
          :certification,
          created_at: DateTime.tomorrow.end_of_day,
          updated_at: DateTime.tomorrow.end_of_day
        )
        expect(
          Certification.between_dates_picked(
            DateTime.yesterday.beginning_of_day,
            DateTime.now.end_of_day
          ).count
        ).to eq(2)
        expect(
          Certification.between_dates_picked(
            3.days.ago.beginning_of_day,
            2.days.ago.beginning_of_day
          ).count
        ).to eq(0)
        expect(
          Certification.between_dates_picked(
            3.days.ago.beginning_of_day,
            3.days.from_now
          ).count
        ).to eq(3)
      end
    end

    context "#default_scope" do
      it "should return only active certifications" do
        3.times { create(:certification) }
        2.times { create(:certification, :inactive) }
        expect(Certification.count).to eq(3)
      end
    end

    context "#inactive" do
      it "should return only inactive certifications (active: false)" do
        3.times { create(:certification) }
        2.times { create(:certification, :inactive) }
        expect(Certification.inactive.count).to eq(2)
      end
    end

    context "#filter_by_attribute" do
      it "should filter by user name, training name or demotions reason" do
        3.times { create(:certification) }
        2.times { create(:certification, :inactive) }
        2.times do
          create(:certification, :inactive, demotion_reason: "This is a reason")
        end
        cert_filtered = Certification.filter_by_attribute("This is a reason")
        expect(cert_filtered.count).to eq(2)
        expect(cert_filtered.pluck(:demotion_reason).uniq).to eq(
          ["This is a reason"]
        )
      end
    end
  end

  describe "Methods" do
    context "#trainer" do
      it "should return the name of the trainer" do
        certification = create(:certification)
        training_session = certification.training_session
        user = training_session.user
        expect(certification.trainer.name).to eq(User.find(user.id).name)
      end
    end

    context "#certify_user" do
      it "should certify user" do
        user = create(:user, :regular_user)
        training_session = create(:training_session, level: "Beginner")
        expect do
          Certification.certify_user(training_session.id, user.id, training_session.level)
        end.to change { Certification.count }.by(1)
        expect(
          Certification.find_by(
            user: user,
            training_session: training_session,
            level: training_session.level
          ).present?
        ).to eq(true)
      end
    end

    context "#get_badge_path" do
      it "should return bronze path for beginners" do
        training_session = create(:training_session, level: "Beginner")
        certification =
          create(:certification, training_session: training_session)
        expect(certification.get_badge_path).to eq("images/badges/bronze.png")
      end

      it "should return silver path for Intermediate" do
        training_session = create(:training_session, level: "Intermediate")
        certification =
          create(:certification, training_session: training_session)
        expect(certification.get_badge_path).to eq("images/badges/silver.png")
      end

      it "should return gold path for Advanced" do
        training_session = create(:training_session, level: "Advanced")
        certification =
          create(:certification, training_session: training_session)
        expect(certification.get_badge_path).to eq("images/badges/golden.png")
      end
    end

    context "#highest_level" do
      it "should certify user" do
        user = create(:user, :regular_user)
        training = create(:training)
        ts1 = create(:training_session, training: training)
        ts1.users << user
        ts2 =
          create(:training_session, training: training, level: "Intermediate")
        ts2.users << user
        create(:certification, training_session: ts1, user: user, level: ts1.level, training: ts1.training)
        create(:certification, training_session: ts2, user: user, level: ts2.level, training: ts2.training)
        expect(user.certifications.highest_level.count).to eq(1)
        expect(
          user.certifications.highest_level.last.training_session.level
        ).to eq("Intermediate")
      end
    end
  end

  describe "Chunk 12: awarding rules and levels" do
    let(:training) { create(:training) }
    let(:ts) { create(:training_session, training: training, level: "Beginner") }
    let(:user) { create(:user, :regular_user) }

    it "requires a level among Beginner/Intermediate/Advanced" do
      cert = Certification.new(user: user, level: "Expert")
      expect(cert).not_to be_valid
      expect(cert.errors[:level]).to eq(["A level is required."])
      expect(Certification.new(user: user, level: "Advanced")).to be_valid
    end

    it "certify_user creates an active certification without checking for duplicates or exam results" do
      expect { 2.times { Certification.certify_user(ts.id, user.id, "Beginner") } }.to change(Certification, :count).by(2)
    end

    it "certify_user returns an unsaved record for an invalid level" do
      cert = Certification.certify_user(ts.id, user.id, "Nope")
      expect(cert).not_to be_persisted
    end

    it "resolves training and trainer through the training session" do
      cert = create(:certification, user: user, training_session: ts, training: training)
      expect(cert.training).to eq(training)
      expect(cert.trainer).to eq(ts.user)
      expect(cert.get_name_en).to eq(training.name_en)
      expect(cert.get_skill_id).to eq(training.skill_id)
    end

    it "existent_certification finds a certification of the same training at the same session level, else false" do
      create(:certification, user: user, training_session: ts, training: training, level: "Beginner")
      expect(Certification.existent_certification(user, training, "Beginner")).to be_a(Certification)
      expect(Certification.existent_certification(user, training, "Advanced")).to be(false)
    end

    it "highest_level keeps only the top-level certifications per training" do
      adv = create(:training_session, training: training, level: "Advanced")
      create(:certification, user: user, training_session: ts, training: training, level: "Beginner")
      top = create(:certification, user: create(:user), training_session: adv, training: training, level: "Advanced")
      expect(Certification.highest_level).to eq([top])
    end

    it "demoted (inactive) certifications disappear from the default scope but not from unscoped" do
      cert = create(:certification, user: user, training_session: ts, training: training)
      cert.update!(active: false)
      expect(user.certifications.reload).to be_empty
      expect(Certification.unscoped.where(id: cert.id)).to exist
    end
  end
end
