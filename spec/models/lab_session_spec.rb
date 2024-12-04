require "rails_helper"

RSpec.describe LabSession, type: :model do
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

  describe "Methods" do
    context "#"
  end
end
