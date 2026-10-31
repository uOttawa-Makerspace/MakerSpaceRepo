require "rails_helper"

# Chunk 15: RfidController. card_number has two callers: Raspberry Pi tap boxes
# (JSON {rfid, mac_address}, no credentials, frozen firmware, registered readers
# only) and the React app (staff session / Bearer JWT with {rfid, space_id}).
# get_unset_rfids is staff-only.
RSpec.describe "RFID endpoints", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  include_context "with test cable adapter"

  let(:space) { create(:space) }
  let(:pi_reader) { create(:pi_reader, space: space) }
  let(:owner) { create(:user, :regular_user) }
  let!(:rfid) { create(:rfid, user: owner, mac_address: pi_reader.pi_mac_address) }

  def tap_card(card: rfid.card_number, **extra)
    post rfid_card_number_path, params: { rfid: card, mac_address: pi_reader.pi_mac_address }.merge(extra), as: :json
  end

  def tap_card_with(mac:, card: rfid.card_number)
    post rfid_card_number_path, params: { rfid: card, mac_address: mac }, as: :json
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

    it "accepts the registered mac in any case, with hyphens or padding (A10 review: MAC normalization)" do
      mac = pi_reader.pi_mac_address
      ["#{mac.upcase}", mac.tr(":", "-"), "  #{mac.upcase.tr(':', '-')} "].each do |variant|
        post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: variant }, as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    it "accepts a lower-case tap for a reader stored upper-case before normalization existed" do
      pi_reader.update_column(:pi_mac_address, pi_reader.pi_mac_address.upcase)
      tap_card_with(mac: pi_reader.pi_mac_address.downcase)
      expect(response).to have_http_status(:ok)
      expect(LabSession.where(user: owner).active.pluck(:space_id)).to eq([space.id])
    end

    it "stores the registered reader's own mac on the session, tap and sign_in rows whatever variant was tapped" do
      tap_card_with(mac: pi_reader.pi_mac_address.upcase.tr(":", "-"))
      expect(LabSession.where(user: owner).last.mac_address).to eq(pi_reader.pi_mac_address)
      expect(TapBoxLog.where(event_type: [TapBoxLog::CARD_TAP, TapBoxLog::SIGN_IN]).pluck(:mac_address).uniq).to eq([pi_reader.pi_mac_address])
      tap_card_with(mac: pi_reader.pi_mac_address.upcase)
      expect(TapBoxLog.where(event_type: TapBoxLog::SIGN_OUT).last.mac_address).to eq(pi_reader.pi_mac_address)
    end

    # FIXED(D-EQ01): a guest without a registered mac cannot tap, whatever the card or space_id
    it "answers 401 and changes nothing for an unknown mac, even with a known card" do
      expect {
        post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: "aa:bb:cc:dd:ee:ff", space_id: space.id }, as: :json
      }.not_to change { [LabSession.count, PiReader.count, Rfid.count] }
      expect(response).to have_http_status(:unauthorized)
      expect(body).to eq(error: "Unauthorized")
    end

    it "answers 401 for a guest with a space_id but no mac" do
      expect {
        post rfid_card_number_path, params: { rfid: rfid.card_number, space_id: space.id }, as: :json
      }.not_to change { [LabSession.count, TapBoxLog.where.not(message: TapBoxLog::UNKNOWN_READER_MESSAGE).count] }
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
      }.not_to change { [PiReader.count, Rfid.count, TapBoxLog.where.not(message: TapBoxLog::UNKNOWN_READER_MESSAGE).count] }
      expect(response).to have_http_status(:unauthorized)
    end

    # FIXED(A10 review item 7): legacy self-registered PiReader rows (no space) are not registered
    it "answers 401 for a legacy space-less reader row, like an unknown mac, and traces it" do
      legacy = create(:pi_reader, space: nil)
      expect {
        post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: legacy.pi_mac_address }, as: :json
      }.not_to change { [LabSession.count, Rfid.count, PiReader.count] }
      expect(response).to have_http_status(:unauthorized)
      expect(body).to eq(error: "Unauthorized")
      expect(TapBoxLog.where(message: TapBoxLog::UNKNOWN_READER_MESSAGE).pluck(:mac_address)).to eq([legacy.pi_mac_address])
    end

    it "creates no temporary Rfid for a new card on a space-less reader" do
      legacy = create(:pi_reader, space: nil)
      expect {
        post rfid_card_number_path, params: { rfid: "NEWCARD", mac_address: legacy.pi_mac_address }, as: :json
      }.not_to change(Rfid, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    it "works as soon as an admin associates the legacy row with a space" do
      legacy = create(:pi_reader, space: nil)
      legacy.update!(space: space)
      tap_card_with(mac: legacy.pi_mac_address)
      expect(response).to have_http_status(:ok)
      expect(LabSession.where(user: owner).active.pluck(:space_id)).to eq([space.id])
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

    it "never stores a stringified hash/array mac from a staff tap (sessions and logs get nil)" do
      headers = { "Authorization" => "Bearer #{create(:user, :staff).token}" }
      [{ a: 1 }, [1, 2]].each do |bad|
        post rfid_card_number_path, params: { rfid: rfid.card_number, space_id: space.id, mac_address: bad }, headers: headers, as: :json
        expect(response).to have_http_status(:ok)
      end
      expect(LabSession.where(user: owner).pluck(:mac_address).uniq).to eq([nil])
      expect(TapBoxLog.where.not(mac_address: nil)).to be_empty
    end

    it "stores a normalized unregistered mac from a staff tap" do
      headers = { "Authorization" => "Bearer #{create(:user, :staff).token}" }
      post rfid_card_number_path, params: { rfid: rfid.card_number, space_id: space.id, mac_address: " AA-BB-CC-00-11-22" }, headers: headers, as: :json
      expect(LabSession.where(user: owner).last.mac_address).to eq("aa:bb:cc:00:11:22")
    end

    it "answers 422 no_space for a staff tap that names neither a space nor a reader with a space" do
      legacy = create(:pi_reader, space: nil)
      post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: legacy.pi_mac_address }, headers: { "Authorization" => "Bearer #{create(:user, :staff).token}" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(TapBoxLog.where(event_type: TapBoxLog::ERROR).last.details["reason"]).to eq("no_space")
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

    it "opens the session for exactly 6 hours from the tap (frozen time)" do
      freeze_time do
        tap_card
        session_row = LabSession.where(user: owner).last
        expect(session_row.sign_in_time).to eq(Time.zone.now)
        expect(session_row.sign_out_time).to eq(Time.zone.now + 6.hours)
      end
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
      }.not_to change { [PiReader.count, TapBoxLog.where.not(message: TapBoxLog::UNKNOWN_READER_MESSAGE).count] }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # A10 review item 3: unregistered readers leave a bounded trace so an admin can discover their MAC
  describe "unregistered reader discovery trace" do
    let(:new_mac) { "de:ad:be:ef:00:01" }

    def trace_rows = TapBoxLog.where(message: TapBoxLog::UNKNOWN_READER_MESSAGE)

    it "writes one WARNING row (just the mac and the time) and no PiReader for an unknown reader" do
      expect { tap_card_with(mac: new_mac.upcase.tr(":", "-")) }.to change(trace_rows, :count).by(1).and change(PiReader, :count).by(0)
      expect(trace_rows.last).to have_attributes(event_type: TapBoxLog::WARNING, mac_address: new_mac, card_number: nil, user_id: nil, space_id: nil)
    end

    it "does not broadcast the trace row to the tap box console, while other rows still are" do
      expect { tap_card_with(mac: new_mac) }.not_to have_broadcasted_to("tap_box_console")
      expect { tap_card }.to have_broadcasted_to("tap_box_console").at_least(:once)
    end

    it "writes at most one row per mac per hour, then again after the hour" do
      3.times { tap_card_with(mac: new_mac) }
      expect(trace_rows.count).to eq(1)
      tap_card_with(mac: "de:ad:be:ef:00:02")
      expect(trace_rows.count).to eq(2)
      travel_to(61.minutes.from_now) { tap_card_with(mac: new_mac) }
      expect(trace_rows.where(mac_address: new_mac).count).to eq(2)
    end

    it "writes nothing for malformed macs, a missing mac or a non-string mac" do
      ["not a mac", "de:ad:be:ef:00", "zz:zz:zz:zz:zz:zz", "a" * 500].each { |bad| tap_card_with(mac: bad) }
      post rfid_card_number_path, params: { rfid: "X" }, as: :json
      post rfid_card_number_path, params: { rfid: "X", mac_address: { a: 1 } }, as: :json
      expect(trace_rows.count).to eq(0)
    end

    it "writes nothing once the tight per-IP rejected-tap limit is hit" do
      counts = Hash.new(0)
      allow(RateLimitCounter).to receive(:increment) { |key, *| counts[key] += 1 }
      11.times { |i| tap_card_with(mac: "de:ad:be:ef:00:%02x" % i) }
      expect(response).to have_http_status(:too_many_requests)
      expect(trace_rows.count).to eq(10)
    end

    it "writes nothing for a registered reader or a staff tap" do
      tap_card
      post rfid_card_number_path, params: { rfid: rfid.card_number, space_id: space.id, mac_address: new_mac }, headers: { "Authorization" => "Bearer #{create(:user, :staff).token}" }, as: :json
      expect(trace_rows.count).to eq(0)
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

    context "with many unset cards in two spaces" do
      let(:other_space) { create(:space) }
      let(:other_reader) { create(:pi_reader, space: other_space) }

      before do
        unset.destroy!
        # own[0] is the newest (1 minute ago) ... own[6] the oldest (7 minutes ago), all tapped at this space
        @own = (1..7).map do |n|
          create(:rfid, user: nil, mac_address: pi_reader.pi_mac_address).tap { |c| c.update_columns(updated_at: n.minutes.ago) }
        end
        # even newer, but tapped at a reader of another space
        @foreign = create(:rfid, user: nil, mac_address: other_reader.pi_mac_address).tap { |c| c.update_columns(updated_at: 10.seconds.ago) }
        # a card that is linked to a user is never "unset"
        create(:rfid, user: owner, mac_address: pi_reader.pi_mac_address)
      end

      it "returns at most 5 cards, newest first, only those tapped at the staff member's space readers" do
        staff = log_in!(create(:user, :staff))
        staff.update!(space: space)

        get rfid_get_unset_rfids_path

        expect(body.map { |c| c[:cardNumber] }).to eq(@own.first(5).map(&:card_number))
        expect(body.first[:tappedAt]).to eq("Tapped at #{space.name} 1 minute ago")
        expect(body.last[:tappedAt]).to eq("Tapped at #{space.name} 5 minutes ago")
      end

      it "scopes a staff member of the other space to that space's readers" do
        staff = log_in!(create(:user, :staff))
        staff.update!(space: other_space)

        get rfid_get_unset_rfids_path

        expect(body).to eq([{ cardNumber: @foreign.card_number, tappedAt: "Tapped at #{other_space.name} less than a minute ago" }])
      end

      it "gives an admin without a space the newest 5 across all spaces" do
        sign_in_as(:admin)

        get rfid_get_unset_rfids_path

        expect(body.map { |c| c[:cardNumber] }).to eq([@foreign, *@own.first(4)].map(&:card_number))
      end
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
      allow(RateLimitCounter).to receive(:increment) { |key, *| counts[key] += 1 }
    end

    it "allows 60 taps a minute per reader mac, then answers 429 and taps nothing" do
      60.times { tap_card; expect(response).not_to have_http_status(:too_many_requests) }
      expect { tap_card }.not_to change { [TapBoxLog.count, LabSession.count] }
      expect(response).to have_http_status(:too_many_requests)
      expect(body).to eq(error: "Too many requests")
    end

    # Production readers send real MACs and short non-MAC identifiers: no format gate, only bounds.
    it "still taps and matches a reader registered with a 4-character identifier" do
      short = create(:pi_reader, space: space, pi_mac_address: "ab12")
      tap_card_with(mac: "AB12")
      expect(response).to have_http_status(:ok)
      expect(LabSession.where(user: owner).active.pluck(:space_id)).to eq([space.id])
      expect(counts.keys.grep(/mac:/).map(&:length).max).to be < 100
      expect(short.reload.pi_mac_address).to eq("ab12")
    end

    it "still matches a MAC whose stored row has a trailing newline" do
      pi_reader.update_column(:pi_mac_address, "#{pi_reader.pi_mac_address}\n")
      tap_card_with(mac: pi_reader.pi_mac_address.strip)
      expect(response).to have_http_status(:ok)
    end

    it "writes no key longer than about 100 characters for a 5000-character identifier, and matches no reader" do
      post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: "a" * 5_000 }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(counts.keys).not_to be_empty
      expect(counts.keys.grep(/mac:/)).to be_empty
      expect(counts.keys.map(&:length).max).to be < 100
      expect(LabSession.count).to eq(0)
    end

    it "treats an identifier with a control character as missing (ip key, rejected path, nothing stored)" do
      ["aa:bb:\u0000cc", "aa\tbb:cc:dd:ee:ff", "ab\u001b12"].each do |bad|
        post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: bad }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
      expect(counts.keys.grep(/mac:/)).to be_empty
      expect(LabSession.count).to eq(0)
    end

    it "uses a fixed-length digest of the identifier in the per-reader key" do
      tap_card
      key = counts.keys.find { |k| k.include?("rfid:tap:mac:") }
      expect(key).to eq("rate-limit:rfid:tap:mac:#{Digest::SHA256.hexdigest(pi_reader.pi_mac_address)[0, 32]}|ip:127.0.0.1")
    end

    it "creates no per-reader key once the source IP is over its ceiling" do
      counts["rate-limit:rfid:tap-ip:127.0.0.1"] = 600
      3.times { |i| post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: "id#{i}" }, as: :json }
      expect(response).to have_http_status(:too_many_requests)
      expect(counts.keys.grep(/mac:/)).to be_empty
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

    it "caps all taps per source IP at 600 a minute" do
      counts["rate-limit:rfid:tap-ip:127.0.0.1"] = 600
      tap_card
      expect(response).to have_http_status(:too_many_requests)
    end

    describe "per reader mac AND source IP (A10 review: a known MAC cannot lock the door out)" do
      let(:attacker) { { "REMOTE_ADDR" => "203.0.113.9" } }

      it "lets a flood from another IP exhaust only its own bucket, not the real reader's" do
        61.times { post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: pi_reader.pi_mac_address }, headers: attacker, as: :json }
        expect(response).to have_http_status(:too_many_requests)
        tap_card # the real reader, fixed IP 127.0.0.1
        expect(response).to have_http_status(:ok)
        expect(body[:success]).to eq("RFID sign in")
      end

      it "treats mac case variants as one bucket for the same IP" do
        60.times { tap_card }
        tap_card_with(mac: pi_reader.pi_mac_address.upcase)
        expect(response).to have_http_status(:too_many_requests)
      end
    end

    describe "rejected taps (unknown mac) per IP" do
      def bad_tap(i = 0, headers: {})
        post rfid_card_number_path, params: { rfid: "X", mac_address: "00:00:00:00:00:%02x" % i }, headers: headers, as: :json
      end

      it "answers 401 ten times a minute per IP, then 429" do
        10.times { |i| bad_tap(i); expect(response).to have_http_status(:unauthorized) }
        bad_tap(11)
        expect(response).to have_http_status(:too_many_requests)
      end

      it "does not throttle the real reader on the same IP, nor other IPs' rejections" do
        11.times { |i| bad_tap(i) }
        tap_card
        expect(response).to have_http_status(:ok)
        bad_tap(1, headers: { "REMOTE_ADDR" => "203.0.113.10" })
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
