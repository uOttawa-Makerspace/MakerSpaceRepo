require "rails_helper"

RSpec.describe LabSession, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:space).without_validating_presence }
    end
  end

  describe "Scopes" do
    context "#between_dates_picked" do
      it "should get the dates" do
        create(
          :lab_session,
          created_at: DateTime.yesterday.end_of_day,
          updated_at: DateTime.yesterday.end_of_day
        )
        create(
          :lab_session,
          created_at: DateTime.now.end_of_day,
          updated_at: DateTime.now.end_of_day
        )
        create(
          :lab_session,
          created_at: DateTime.tomorrow.end_of_day,
          updated_at: DateTime.tomorrow.end_of_day
        )
        expect(
          LabSession.between_dates_picked(
            DateTime.yesterday.beginning_of_day,
            DateTime.now.end_of_day
          ).count
        ).to eq(2)
        expect(
          LabSession.between_dates_picked(
            3.days.ago.beginning_of_day,
            2.days.ago.beginning_of_day
          ).count
        ).to eq(0)
        expect(
          LabSession.between_dates_picked(
            3.days.ago.beginning_of_day,
            3.days.from_now
          ).count
        ).to eq(3)
      end
    end

    context "#active" do
      it "counts a session as over once its sign out time is reached" do
        freeze_time do
          lab_user = create(:user, :regular_user)
          ending = create(:lab_session, user: lab_user, sign_in_time: 1.hour.ago, sign_out_time: Time.zone.now)
          ahead = create(:lab_session, user: lab_user, sign_in_time: 1.hour.ago, sign_out_time: 1.second.from_now)
          expect(LabSession.active).to contain_exactly(ahead)
          expect(LabSession.active_for_user(lab_user)).to contain_exactly(ahead)
          expect(ending.reload.sign_out).to be_nil
          expect(ending.sign_out_time).to eq(Time.zone.now)
        end
      end
    end

    context "#active_for_user" do
      it "should return only active lab sessions" do
        lab_user = create(:user, :regular_user)
        current_session =
          create(
            :lab_session,
            user: lab_user,
            sign_in_time: DateTime.now - 3.hours,
            # Still signed in to space
            sign_out_time: DateTime.now + -3.hours + 8.hours
          )
        old_session =
          create(
            :lab_session,
            user: lab_user,
            # signed in yesterday
            sign_in_time: DateTime.now - 1.day,
            sign_out_time: DateTime.now - 1.day + 3.hours
          )
        expect(LabSession.active_for_user(lab_user).count).to eq(1)
        LabSession.active_for_user(lab_user).last.sign_out
        current_session.reload
        old_session.reload
        # sign out now in the past
        expect(current_session.sign_out_time).to be <= DateTime.now
        # Make sure we don't affect other records ;-;
        expect(
          current_session.sign_out_time
        ).to_not eq old_session.sign_out_time
      end
    end
  end

  describe ".sign_in" do
    let(:space) { create(:space) }
    let(:user) { create(:user, :regular_user) }

    it "opens a session of LabSession::LENGTH and says so" do
      freeze_time do
        expect(LabSession.sign_in(user, space)).to be(true)
        row = LabSession.sole
        expect(row).to have_attributes(user_id: user.id, space_id: space.id, sign_in_time: Time.zone.now,
                                       sign_out_time: Time.zone.now + 6.hours, mac_address: nil)
      end
      expect(LabSession::LENGTH).to eq(6.hours)
    end

    it "records the reader's mac address" do
      LabSession.sign_in(user, space, mac_address: "aa:bb")
      expect(LabSession.sole.mac_address).to eq("aa:bb")
    end

    it "keeps the session of a user already in the space" do
      LabSession.sign_in(user, space)
      expect(LabSession.sign_in(user, space)).to be(false)
      expect(LabSession.where(user_id: user.id).count).to eq(1)
    end

    it "signs in again once the earlier session ended, and to another space while in the first" do
      create(:lab_session, user: user, space: space, sign_in_time: 3.hours.ago, sign_out_time: 1.hour.ago)
      expect(LabSession.sign_in(user, space)).to be(true)
      expect(LabSession.sign_in(user, create(:space))).to be(true)
      expect(LabSession.active_for_user(user).count).to eq(2)
    end
  end

  describe ".sign_out" do
    let(:space) { create(:space) }
    let(:other_space) { create(:space) }
    let(:user) { create(:user, :regular_user) }

    it "ends every active session in the space and leaves other spaces and ended sessions alone" do
      freeze_time do
        a = create(:lab_session, user: user, space: space, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
        b = create(:lab_session, user: user, space: space, sign_in_time: 1.hour.ago, sign_out_time: 3.hours.from_now)
        elsewhere = create(:lab_session, user: user, space: other_space, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
        ended_at = 1.hour.ago
        ended = create(:lab_session, user: user, space: space, sign_in_time: 3.hours.ago, sign_out_time: ended_at)

        expect(LabSession.sign_out(user, space)).to eq(2)
        expect([a, b].map { |row| row.reload.sign_out_time }).to all(eq(Time.zone.now))
        expect(elsewhere.reload.sign_out_time).to be > Time.zone.now
        expect(ended.reload.sign_out_time).to eq(ended_at)
      end
    end

    it "does nothing for a user who is not in the space" do
      expect(LabSession.sign_out(user, space)).to eq(0)
    end
  end

  describe ".sign_out_all" do
    it "ends every active session in the space, for every user, and no other space" do
      space = create(:space)
      mine = create_list(:lab_session, 2, space: space, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
      elsewhere = create(:lab_session, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
      expect(LabSession.sign_out_all(space)).to eq(2)
      expect(mine.map { |row| row.reload.sign_out_time }).to all(be <= Time.zone.now)
      expect(elsewhere.reload.sign_out_time).to be > Time.zone.now
    end
  end

  describe ".count_by_shown_faculty" do
    it "counts each visit under the visitor's shown faculty, a deleted visitor's too, and a visit with no user as unknown" do
      space = create(:space)
      verified = create(:user, :regular_user, faculty: "Arts")
      UoengProfile.create!(user: verified, faculty_code: "GENIE", faculty: "Engineering", source: "email", checked_at: Time.current)
      gone = create(:user, :regular_user, faculty: "Science")
      [verified, verified, gone].each { |user| create(:lab_session, space: space, user: user) }
      gone.soft_delete!
      create(:lab_session, space: space, user: gone).update_columns(user_id: nil)
      expect(LabSession.count_by_shown_faculty).to eq("Engineering" => 2, "Science" => 1, "unknown" => 1)
    end
  end
end
