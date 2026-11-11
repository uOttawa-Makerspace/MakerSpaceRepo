# frozen_string_literal: true

require "rails_helper"

# The toggle of RfidTap#call: sign in, sign out, switch space, and the repeat window that
# ignores a second tap of the same card in the same space soon after the session started.
RSpec.describe RfidTap do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  include_context "with test cable adapter"

  let(:space) { create(:space) }
  let(:other_space) { create(:space) }
  let(:owner) { create(:user, :regular_user) }
  let!(:rfid) { create(:rfid, user: owner) }

  def tap_in(space: self.space)
    described_class.call(card: rfid.card_number, space: space, mac_address: nil)
  end

  # Strictly in the future: under frozen time a session signed out at this very instant still counts as active.
  def active_sessions = LabSession.where(user: owner).where("sign_out_time > ?", Time.current)

  it "uses a 60 second repeat window" do
    expect(described_class::REPEAT_WINDOW).to eq(60.seconds)
  end

  it "signs in a user with no active session and queues the membership check" do
    expect { expect(tap_in.outcome).to eq(:sign_in) }.to have_enqueued_job(CardTapJob).with(rfid, space.id)
    expect(active_sessions.pluck(:space_id)).to eq([space.id])
  end

  describe "a second tap of the same card in the same space" do
    it "is answered as signed in, within the window of the session start, and changes nothing" do
      freeze_time do
        tap_in
        travel(described_class::REPEAT_WINDOW - 1.second)
        session = active_sessions.sole
        sign_outs = TapBoxLog.where(event_type: TapBoxLog::SIGN_OUT)
        expect { expect(tap_in.outcome).to eq(:sign_in) }.not_to have_enqueued_job(CardTapJob)
        expect(LabSession.where(user: owner).count).to eq(1)
        expect(sign_outs.count).to eq(0)
        expect(session.reload.sign_out_time).to be > Time.current
        expect(active_sessions.sole).to eq(session)
      end
    end

    it "does not broadcast a table update or a modal" do
      freeze_time do
        tap_in
        expect { tap_in }.not_to have_broadcasted_to("signed_in_table_space_#{space.id}").from_channel(Turbo::StreamsChannel)
        expect { tap_in }.not_to have_broadcasted_to("space_event_#{space.id}")
      end
    end

    it "measures the window from the session start, not from the last tap" do
      freeze_time do
        tap_in
        travel(40.seconds)
        expect(tap_in.outcome).to eq(:sign_in)
        travel(30.seconds)
        # 70 seconds after the session started, though only 30 after the repeat tap
        expect(tap_in.outcome).to eq(:sign_out)
        expect(active_sessions).to be_empty
      end
    end

    it "signs out once the window has passed" do
      freeze_time do
        tap_in
        travel(described_class::REPEAT_WINDOW + 1.second)
        expect(tap_in.outcome).to eq(:sign_out)
        expect(active_sessions).to be_empty
      end
    end

    it "signs out at exactly the window length" do
      freeze_time do
        tap_in
        travel(described_class::REPEAT_WINDOW)
        expect(tap_in.outcome).to eq(:sign_out)
      end
    end

    it "starts a new window with the next sign in" do
      freeze_time do
        tap_in
        travel(described_class::REPEAT_WINDOW + 1.second)
        expect(tap_in.outcome).to eq(:sign_out)
        expect(tap_in.outcome).to eq(:sign_in)
        session = active_sessions.sole
        expect(session.sign_in_time).to eq(Time.current)
        expect(tap_in.outcome).to eq(:sign_in)
        expect(active_sessions.sole).to eq(session)
      end
    end
  end

  describe "a tap in a different space within the window" do
    it "is a space switch: signs out of the first space and in to the second" do
      freeze_time do
        tap_in
        travel(10.seconds)
        expect(tap_in(space: other_space).outcome).to eq(:sign_in)
        expect(active_sessions.pluck(:space_id)).to eq([other_space.id])
        expect(TapBoxLog.where(event_type: TapBoxLog::SIGN_OUT).last.details).to include("action" => "space_switch")
      end
    end

    it "then ignores a repeat in the second space, and signs out after the window" do
      freeze_time do
        tap_in
        travel(10.seconds)
        tap_in(space: other_space)
        travel(10.seconds)
        expect(tap_in(space: other_space).outcome).to eq(:sign_in)
        expect(active_sessions.count).to eq(1)
        travel(described_class::REPEAT_WINDOW)
        expect(tap_in(space: other_space).outcome).to eq(:sign_out)
      end
    end
  end

  it "signs out of every space when switching from a user signed in to two spaces" do
    create(:lab_session, user: owner, space: space, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
    create(:lab_session, user: owner, space: other_space, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
    third = create(:space)
    expect(tap_in(space: third).outcome).to eq(:sign_in)
    expect(active_sessions.pluck(:space_id)).to eq([third.id])
  end

  it "signs out a session opened by staff over an hour ago when the card is tapped" do
    create(:lab_session, user: owner, space: space, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
    expect(tap_in.outcome).to eq(:sign_out)
  end
end
