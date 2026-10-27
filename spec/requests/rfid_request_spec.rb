require "rails_helper"

# Chunk 15: RfidController. card_number has two callers: Raspberry Pi tap boxes
# (JSON {rfid, mac_address}, no credentials, frozen firmware, registered readers
# only) and the React app (staff session / Bearer JWT with {rfid, space_id}).
# get_unset_rfids is staff-only.
RSpec.describe "RFID endpoints", type: :request do
  include ActiveJob::TestHelper

  include_context "with test cable adapter"

  let(:space) { create(:space) }
  let(:pi_reader) { create(:pi_reader, space: space) }
  let(:owner) { create(:user, :regular_user) }
  let!(:rfid) { create(:rfid, user: owner, mac_address: pi_reader.pi_mac_address) }

  def tap_card(card: rfid.card_number, **extra)
    post rfid_card_number_path, params: { rfid: card, mac_address: pi_reader.pi_mac_address }.merge(extra), as: :json
  end

  def body
    JSON.parse(response.body, symbolize_names: true)
  end

  describe "POST /rfid/card_number as a Pi reader (no credentials, registered mac only)" do
    # FIXED(D-EQ01): a registered reader mac is the only credential a guest can present
    it "signs the card owner in for a registered reader" do
      expect { tap_card }.to change { LabSession.where(user: owner, space: space).active.count }.from(0).to(1)
      expect(response).to have_http_status(:ok)
      expect(body[:success]).to eq("RFID sign in")
      expect(session[:user_id]).to be_nil
    end

    it "signs the same user out again" do
      tap_card
      tap_card
      expect(body[:success]).to eq("RFID sign out")
      expect(LabSession.where(user: owner).active).to be_empty
    end

    # FIXED(D-EQ01): a guest without a registered mac cannot tap, whatever the card or space_id
    it "answers 401 and changes nothing for an unknown mac, even with a known card" do
      expect {
        post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: "aa:bb:cc:dd:ee:ff", space_id: space.id }, as: :json
      }.not_to change { [LabSession.count, TapBoxLog.count, PiReader.count, Rfid.count] }
      expect(response).to have_http_status(:unauthorized)
      expect(body).to eq(error: "Unauthorized")
    end

    it "answers 401 for a guest with a space_id but no mac" do
      expect {
        post rfid_card_number_path, params: { rfid: rfid.card_number, space_id: space.id }, as: :json
      }.not_to change { [LabSession.count, TapBoxLog.count] }
      expect(response).to have_http_status(:unauthorized)
    end

    it "answers 401 for a guest with neither mac nor space_id, and for a non-string mac" do
      post rfid_card_number_path, params: { rfid: rfid.card_number }, as: :json
      expect(response).to have_http_status(:unauthorized)
      post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: { a: 1 } }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(LabSession.count).to eq(0)
    end

    it "does not let a Pi redirect its tap to another space with space_id" do
      other = create(:space)
      post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: pi_reader.pi_mac_address, space_id: other.id }, as: :json
      expect(LabSession.where(user: owner).active.pluck(:space_id)).to eq([space.id])
    end

    # FIXED(D-EQ03): an unknown mac no longer creates a PiReader, a temporary Rfid or TapBoxLog rows
    it "creates no PiReader, Rfid or TapBoxLog rows for an unknown mac with a new card" do
      expect {
        post rfid_card_number_path, params: { rfid: "BRANDNEW1", mac_address: "aa:bb:cc:dd:ee:ff" }, as: :json
      }.not_to change { [PiReader.count, Rfid.count, TapBoxLog.count] }
      expect(response).to have_http_status(:unauthorized)
    end

    it "answers 422 for a registered reader that has no space assigned" do
      unassigned = create(:pi_reader, space: nil)
      expect {
        post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: unassigned.pi_mac_address }, as: :json
      }.not_to change(LabSession, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(TapBoxLog.where(event_type: TapBoxLog::ERROR).last.details["reason"]).to eq("no_space")
    end

    # FIXED(D-EQ02): the response carries only `success`, no membership/safety-sheet state of the card owner
    it "returns only the success string, for sign in and sign out" do
      tap_card
      expect(body).to eq(success: "RFID sign in")
      tap_card
      expect(body).to eq(success: "RFID sign out")
    end

    it "returns only the success string to a staff Bearer JWT too" do
      post rfid_card_number_path, params: { rfid: rfid.card_number, space_id: space.id }, headers: { "Authorization" => "Bearer #{create(:user, :staff).token}" }, as: :json
      expect(body).to eq(success: "RFID sign in")
    end
  end

  describe "POST /rfid/card_number as the React app (staff session or Bearer JWT with space_id)" do
    def tap_as(headers, **params)
      post rfid_card_number_path, params: { rfid: rfid.card_number, space_id: space.id }.merge(params), headers: headers, as: :json
    end

    def bearer(user) = { "Authorization" => "Bearer #{user.token}" }

    %i[staff admin].each do |role|
      it "signs the card owner in then out for a #{role} Bearer JWT without any session" do
        user = create(:user, role)
        expect { tap_as(bearer(user)) }.to change { LabSession.where(user: owner, space: space).active.count }.from(0).to(1)
        expect(response).to have_http_status(:ok)
        expect(body[:success]).to eq("RFID sign in")
        tap_as(bearer(user))
        expect(body[:success]).to eq("RFID sign out")
      end
    end

    it "accepts a staff browser session" do
      sign_in_as(:staff)
      tap_as({})
      expect(response).to have_http_status(:ok)
      expect(body[:success]).to eq("RFID sign in")
    end

    %i[regular volunteer].each do |role|
      it "answers 401 for a #{role} session with a space_id" do
        sign_in_as(role)
        expect { tap_as({}) }.not_to change(LabSession, :count)
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it "answers 401 for a regular user's Bearer JWT and for a garbage token" do
      expect { tap_as(bearer(create(:user, :regular_user))) }.not_to change(LabSession, :count)
      expect(response).to have_http_status(:unauthorized)
      tap_as({ "Authorization" => "Bearer nope" })
      expect(response).to have_http_status(:unauthorized)
    end

    it "answers 422 for a staff tap with an unknown space_id and no registered mac" do
      tap_as(bearer(create(:user, :staff)), space_id: 0)
      expect(response).to have_http_status(:unprocessable_content)
      expect(LabSession.count).to eq(0)
    end

    it "falls back to a registered reader's space when staff omit space_id" do
      post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: pi_reader.pi_mac_address }, headers: bearer(create(:user, :staff)), as: :json
      expect(body[:success]).to eq("RFID sign in")
    end
  end

  describe "tap in / out persistence" do
    it "persists a LabSession on sign in and logs card_tap, info and sign_in rows" do
      expect { tap_card }.to change(TapBoxLog, :count)
      session_row = LabSession.where(user: owner).last
      expect(session_row.space_id).to eq(space.id)
      expect(session_row.mac_address).to eq(pi_reader.pi_mac_address)
      types = TapBoxLog.order(:id).pluck(:event_type)
      expect(types).to include(TapBoxLog::CARD_TAP, TapBoxLog::INFO, TapBoxLog::SIGN_IN)
      expect(TapBoxLog.where(event_type: TapBoxLog::SIGN_IN).last).to have_attributes(user_id: owner.id, space_id: space.id, card_number: rfid.card_number)
    end

    it "ends the session and logs sign_out on the second tap" do
      tap_card
      expect { tap_card }.to change { TapBoxLog.where(event_type: TapBoxLog::SIGN_OUT).count }.by(1)
      expect(LabSession.where(user: owner).active).to be_empty
    end

    it "lets staff tap with space_id only, and toggles sign in/out (integer space comparison)" do
      staff = create(:user, :staff)
      headers = { "Authorization" => "Bearer #{staff.token}" }
      post rfid_card_number_path, params: { rfid: rfid.card_number, space_id: space.id.to_s }, headers: headers, as: :json
      expect(body[:success]).to eq("RFID sign in")
      post rfid_card_number_path, params: { rfid: rfid.card_number, space_id: space.id.to_s }, headers: headers, as: :json
      expect(body[:success]).to eq("RFID sign out")
    end

    it "closes the old session and opens a new one when tapping at a different space" do
      other_space = create(:space)
      other_reader = create(:pi_reader, space: other_space)
      tap_card
      post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: other_reader.pi_mac_address }, as: :json
      expect(body[:success]).to eq("RFID sign in")
      expect(LabSession.where(user: owner).active.pluck(:space_id)).to eq([other_space.id])
      switch = TapBoxLog.where(event_type: TapBoxLog::SIGN_OUT).last
      expect(switch.details).to include("action" => "space_switch", "previous_space_id" => space.id)
    end

    it "enqueues CardTapJob with the rfid and space on sign in only" do
      expect { tap_card }.to have_enqueued_job(CardTapJob).with(rfid, space.id)
      expect { tap_card }.not_to have_enqueued_job(CardTapJob)
    end

    it "creates a TapBoxLog row that prepends to the tap_box_console Turbo stream" do
      expect { tap_card }.to have_broadcasted_to("tap_box_console").at_least(:once)
    end

    it "broadcasts a table update (and no modal) to the signed-in table stream on sign out" do
      tap_card
      expect { tap_card }.to have_broadcasted_to("signed_in_table_space_#{space.id}").from_channel(Turbo::StreamsChannel)
      expect { tap_card }.not_to have_broadcasted_to("space_event_#{space.id}")
    end

    it "broadcasts the add_user modal to StaffDashboardChannel once CardTapJob has run" do
      create(:membership_tier, title_en: "Faculty membership", title_fr: "Adhesion de la faculte", internal_price: 0, external_price: 0, duration: 4.months.to_i)
      expect {
        perform_enqueued_jobs { tap_card }
      }.to have_broadcasted_to("space_event_#{space.id}").with(
        a_hash_including("add_user" => a_hash_including("id" => owner.id, "username" => owner.username, "name" => owner.name, "email" => owner.email))
      )
    end

    # FIXED(D-EQ05): a missing "Faculty membership" tier is logged to TapBoxLog, the job does not raise and the staff modal is still broadcast
    it "logs a card_tap_job_failure but still broadcasts the modal when the Faculty membership tier is missing" do
      expect {
        expect { perform_enqueued_jobs { tap_card } }.to have_broadcasted_to("space_event_#{space.id}").with(
          a_hash_including("add_user" => a_hash_including("id" => owner.id))
        )
      }.to change { TapBoxLog.where(event_type: TapBoxLog::ERROR).count }.by(1)
      expect(TapBoxLog.where(event_type: TapBoxLog::ERROR).last.details["reason"]).to eq("card_tap_job_failure")
      expect(response).to have_http_status(:ok)
      expect(body).to eq(success: "RFID sign in")
    end

    it "sends no StaffDashboardChannel broadcast until the job runs" do
      expect { tap_card }.not_to have_broadcasted_to("space_event_#{space.id}")
    end
  end

  describe "unknown / unlinked / malformed taps" do
    it "reports a new unknown card on a known reader, creating a temporary Rfid" do
      expect {
        post rfid_card_number_path, params: { rfid: "NEWCARD", mac_address: pi_reader.pi_mac_address }, as: :json
      }.to change(Rfid, :count).by(1)
      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to eq(new_rfid: "Temporary RFID created")
      expect(Rfid.find_by(card_number: "NEWCARD")).to have_attributes(user_id: nil, mac_address: pi_reader.pi_mac_address)
      expect(TapBoxLog.where(event_type: TapBoxLog::WARNING).last.details["reason"]).to eq("new_unknown_card")
    end

    it "reports an unlinked temporary card and refreshes its mac address" do
      temp = create(:rfid, user: nil, mac_address: "old")
      post rfid_card_number_path, params: { rfid: temp.card_number, mac_address: pi_reader.pi_mac_address }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to eq(error: "Temporary RFID already exists")
      expect(temp.reload.mac_address).to eq(pi_reader.pi_mac_address)
    end

    # FIXED(D-EQ04): parameter wrapping is off for RfidController, so a JSON tap without an rfid key is a clean 422
    it "answers 422 for a JSON tap with no rfid key, creating nothing" do
      expect {
        post rfid_card_number_path, params: { mac_address: pi_reader.pi_mac_address }, as: :json
      }.not_to change(Rfid, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to eq(new_rfid: "Error, requires rfid param")
    end

    it "answers 422 when rfid is not a string (hash or array) or the body is empty" do
      [{ a: 1 }, [1]].each do |bad|
        post rfid_card_number_path, params: { rfid: bad, mac_address: pi_reader.pi_mac_address }, as: :json
        expect(response).to have_http_status(:unprocessable_content)
      end
      post rfid_card_number_path, params: {}, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "does not wrap JSON params under :rfid" do
      expect(RfidController._wrapper_options.format).to be_empty
    end

    it "rejects a blank card number (form-encoded) and logs an invalid_rfid error" do
      expect {
        post rfid_card_number_path, params: { mac_address: pi_reader.pi_mac_address }
      }.not_to change(Rfid, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to eq(new_rfid: "Error, requires rfid param")
      expect(TapBoxLog.where(event_type: TapBoxLog::ERROR).last.details["reason"]).to eq("invalid_rfid")
    end

    it "rejects a staff tap without space_id or mac_address and logs no_space" do
      post rfid_card_number_path, params: { rfid: rfid.card_number }, headers: { "Authorization" => "Bearer #{create(:user, :staff).token}" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to eq(new_rfid: "Error, missing space_id or mac_address param")
      expect(TapBoxLog.where(event_type: TapBoxLog::ERROR).last.details["reason"]).to eq("no_space")
    end

    # FIXED(D-EQ03): an unknown reader mac is rejected and is not registered
    it "does not register an unknown reader mac" do
      expect {
        post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: "de:ad:be:ef:00:01" }, as: :json
      }.not_to change { [PiReader.count, TapBoxLog.count] }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /rfid/get_unset_rfids" do
    let!(:unset) { create(:rfid, user: nil, mac_address: pi_reader.pi_mac_address) }

    it "sends a guest to the login page" do
      get rfid_get_unset_rfids_path
      expect(response).to redirect_to(login_path(back_to: rfid_get_unset_rfids_path))
    end

    it "answers a JSON guest with the raw string redirect (not JSON) and status 200" do
      get rfid_get_unset_rfids_path(format: :json)
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("redirect")
    end

    %i[regular volunteer].each do |role|
      it "bounces a #{role} to root with an alert" do
        sign_in_as(role)
        get rfid_get_unset_rfids_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("You cannot access this area.")
      end
    end

    it "lists unset cards of the staff member's space as JSON" do
      staff = log_in!(create(:user, :staff))
      staff.update!(space: space)
      get rfid_get_unset_rfids_path
      expect(response).to have_http_status(:ok)
      expect(body).to eq([{ cardNumber: unset.card_number, tappedAt: "Tapped at #{space.name} less than a minute ago" }])
    end

    it "lets an admin through (staff? covers admins) and lists unset cards across all spaces" do
      sign_in_as(:admin)
      get rfid_get_unset_rfids_path
      expect(response).to have_http_status(:ok)
      expect(body.map { |c| c[:cardNumber] }).to eq([unset.card_number])
    end
  end

  # test env uses :null_store (never counts), so back the limiter's store with a counter
  describe "rate limit (D-EQ03)" do
    let(:counts) { Hash.new(0) }

    before do
      allow(RfidController.cache_store).to receive(:increment) { |key, *| counts[key] += 1 }
    end

    it "allows 60 taps a minute per reader mac, then answers 429 and taps nothing" do
      60.times { tap_card; expect(response).not_to have_http_status(:too_many_requests) }
      expect { tap_card }.not_to change { [TapBoxLog.count, LabSession.count] }
      expect(response).to have_http_status(:too_many_requests)
      expect(body).to eq(error: "Too many requests")
    end

    it "counts per reader, not globally" do
      60.times { tap_card }
      other = create(:pi_reader, space: space)
      post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: other.pi_mac_address }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "counts per staff user for the React app" do
      staff = create(:user, :staff)
      other_staff = create(:user, :staff)
      call = ->(u) { post rfid_card_number_path, params: { rfid: rfid.card_number, space_id: space.id }, headers: { "Authorization" => "Bearer #{u.token}" }, as: :json }
      60.times { call.(staff) }
      call.(staff)
      expect(response).to have_http_status(:too_many_requests)
      # fresh session: the first user's cookie would otherwise win over the bearer token
      other_session = open_session
      other_session.post rfid_card_number_path, params: { rfid: rfid.card_number, space_id: space.id }.to_json,
                                                headers: { "Authorization" => "Bearer #{other_staff.token}", "Content-Type" => "application/json" }
      expect(other_session.response).to have_http_status(:ok)
    end

    it "caps floods of made-up macs per IP at 600 a minute" do
      600.times { |i| post rfid_card_number_path, params: { rfid: "X", mac_address: "00:00:00:00:#{i / 256}:#{i % 256}" }, as: :json }
      expect(response).to have_http_status(:unauthorized)
      post rfid_card_number_path, params: { rfid: "X", mac_address: "ff:ff:ff:ff:ff:ff" }, as: :json
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
