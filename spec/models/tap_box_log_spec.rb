require "rails_helper"

RSpec.describe TapBoxLog, type: :model do
  include_context "with test cable adapter"

  it { should belong_to(:user).optional }
  it { should belong_to(:space).optional }
  it { should validate_presence_of(:event_type) }
  it { should validate_presence_of(:message) }
  it { should validate_inclusion_of(:event_type).in_array(TapBoxLog::EVENT_TYPES) }

  it "knows the seven event types" do
    expect(TapBoxLog::EVENT_TYPES).to eq(%w[card_tap sign_in sign_out error warning info membership_check])
  end

  describe ".log!" do
    it "persists a row with all the fields" do
      user = create(:user, :regular_user)
      space = create(:space)
      log = TapBoxLog.log!(event_type: TapBoxLog::INFO, message: "hi", card_number: "C1", user: user, space: space, mac_address: "m", details: { a: 1 })
      expect(log.reload).to have_attributes(event_type: "info", message: "hi", card_number: "C1", user_id: user.id, space_id: space.id, mac_address: "m")
      expect(log.details).to eq("a" => 1)
    end

    # WART(D-EQ28): log! swallows every failure (returns the logger result, never raises), so an invalid event type silently drops the log row
    it "swallows validation errors and writes nothing" do
      allow(Rails.logger).to receive(:error)
      expect { TapBoxLog.log!(event_type: "bogus", message: "x") }.not_to change(TapBoxLog, :count)
      expect(Rails.logger).to have_received(:error).with(/Failed to write log/)
    end
  end

  describe "broadcast on create" do
    it "prepends the rendered row to the tap_box_console stream" do
      expect { TapBoxLog.log!(event_type: TapBoxLog::INFO, message: "streamed") }.to have_broadcasted_to("tap_box_console").from_channel(Turbo::StreamsChannel)
    end

    it "broadcasts on a stream named tap_box_console with target console-body" do
      TapBoxLog.log!(event_type: TapBoxLog::INFO, message: "streamed row")
      payload = ActionCable.server.pubsub.broadcasts("tap_box_console").last
      expect(payload).to include("console-body").and include("streamed row").and include('action=\"prepend\"')
    end
  end

  describe ".recent" do
    it "returns newest first, capped at 500" do
      old = TapBoxLog.log!(event_type: TapBoxLog::INFO, message: "old")
      old.update_columns(created_at: 1.day.ago)
      fresh = TapBoxLog.log!(event_type: TapBoxLog::INFO, message: "new")
      expect(TapBoxLog.recent.first).to eq(fresh)
      expect(TapBoxLog.recent.to_sql).to match(/LIMIT 500/)
    end
  end

  describe ".purge_old!" do
    it "deletes rows older than 30 days by default and keeps the rest" do
      stale = TapBoxLog.log!(event_type: TapBoxLog::INFO, message: "stale")
      stale.update_columns(created_at: 31.days.ago)
      keep = TapBoxLog.log!(event_type: TapBoxLog::INFO, message: "keep")
      mid = TapBoxLog.log!(event_type: TapBoxLog::INFO, message: "mid")
      mid.update_columns(created_at: 10.days.ago)
      expect(TapBoxLog.purge_old!).to eq(1)
      expect(TapBoxLog.where(id: [stale.id, keep.id, mid.id]).pluck(:id)).to match_array([keep.id, mid.id])
      expect(TapBoxLog.purge_old!(days: 5)).to eq(1)
    end
  end

  describe "named loggers" do
    let(:user) { create(:user, :regular_user) }
    let(:space) { create(:space) }

    it "log_card_tap records the raw tap with details" do
      row = TapBoxLog.log_card_tap(card_number: "C", mac_address: "m", space_id_param: "3")
      expect(row).to have_attributes(event_type: "card_tap", message: "Card tapped on reader")
      expect(row.details).to eq("rfid" => "C", "mac_address" => "m", "space_id_param" => "3")
    end

    it "log_sign_in and log_sign_out name the space" do
      expect(TapBoxLog.log_sign_in(user: user, card_number: "C", space: space, mac_address: "m").message).to eq("#{user.name} signed into #{space.name}")
      expect(TapBoxLog.log_sign_out(user: user, card_number: "C", space: space, mac_address: "m").message).to eq("#{user.name} signed out of #{space.name}")
    end

    it "log_sign_out with a previous space records a space switch" do
      prev = create(:space)
      row = TapBoxLog.log_sign_out(user: user, card_number: "C", space: space, mac_address: "m", previous_space: prev)
      expect(row.message).to eq("#{user.name} signed out of #{prev.name} (switching spaces)")
      expect(row.details).to eq("previous_space_id" => prev.id, "action" => "space_switch")
    end

    it "classifies the warning/error/info loggers" do
      expect(TapBoxLog.log_unlinked_card(card_number: "C", space: space, mac_address: "m").event_type).to eq("warning")
      expect(TapBoxLog.log_new_unknown_card(card_number: "C", space: space, mac_address: "m").event_type).to eq("warning")
      expect(TapBoxLog.log_invalid_rfid(card_number: nil, mac_address: "m", errors: ["bad"]).event_type).to eq("error")
      expect(TapBoxLog.log_no_space_resolved(card_number: "C", mac_address: "m").event_type).to eq("error")
      expect(TapBoxLog.log_new_pi_reader(card_number: "C", mac_address: "m").event_type).to eq("info")
      expect(TapBoxLog.log_membership_check_queued(user: user, card_number: "C", space: space, mac_address: "m").event_type).to eq("info")
      expect(TapBoxLog.log_card_recognized(user: user, card_number: "C", space: space, mac_address: "m", elapsed_ms: 1.5).details).to include("user_email" => user.email, "resolve_time_ms" => 1.5)
    end

    it "log_card_tap_job_failure keeps the exception class and trimmed backtrace" do
      err = begin; raise ArgumentError, "boom"; rescue => e; e; end
      row = TapBoxLog.log_card_tap_job_failure(user: user, card_number: "C", space: space, exception: err)
      expect(row.message).to eq("CardTapJob failed for #{user.name}: boom")
      expect(row.details).to include("reason" => "card_tap_job_failure", "exception_class" => "ArgumentError")
      expect(row.details["backtrace"].size).to be <= 5
    end

    it "membership-check loggers use the membership_check or warning/error types" do
      expect(TapBoxLog.log_not_engineering(user: user, api_details: { "faculty" => "Arts" }).event_type).to eq("membership_check")
      expect(TapBoxLog.log_membership_revocation(user: user, revoked_count: 1, revoked_ids: [1]).event_type).to eq("membership_check")
      expect(TapBoxLog.log_not_engineering(user: user, api_details: {}).message).to include("unknown")
      expect(TapBoxLog.log_no_queryable_identifier(user: user).event_type).to eq("warning")
      expect(TapBoxLog.log_name_mismatch(user: user, uoeng_name: "X").event_type).to eq("warning")
      expect(TapBoxLog.log_student_id_mismatch(user: user, uoeng_student_id: "9").event_type).to eq("warning")
      expect(TapBoxLog.log_slow_api(user: user, elapsed_ms: 5000).event_type).to eq("warning")
      expect(TapBoxLog.log_api_http_error(user: user, http_status: 500, elapsed_ms: 1, response_body: "x" * 600).details["response_body"].length).to eq(500)
      expect(TapBoxLog.log_api_timeout(user: user, elapsed_ms: 1, exception: Timeout::Error.new).event_type).to eq("error")
      expect(TapBoxLog.log_api_bad_json(user: user, exception: StandardError.new("j")).event_type).to eq("error")
    end
  end
end
