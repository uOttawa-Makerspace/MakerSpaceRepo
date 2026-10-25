require "rails_helper"

# Chunk 15: RfidController. RFID card taps come from Raspberry Pi tap boxes.
# card_number is a machine-to-machine endpoint: it has NO authentication
# (no shared secret, no IP allow-list, no env guard) and CSRF is off app-wide
# (D-B26). Anyone on the internet can post a tap for any known card number and
# sign that card's owner in/out of a space, create Rfid / PiReader / TapBoxLog
# rows and trigger broadcasts. get_unset_rfids is staff-only.
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

  let(:status_payload) { { has_membership: false, has_shop_fundamentals: false, signed_consent_form: false } }

  describe "POST /rfid/card_number as an unauthenticated guest (no machine auth at all)" do
    # WART(D-EQ01): RfidController#card_number has no authentication, so a guest can sign any card's owner in/out of a space
    it "lets a guest sign a user in for any known card number" do
      expect { tap_card }.to change { LabSession.where(user: owner, space: space).active.count }.from(0).to(1)
      expect(response).to have_http_status(:ok)
      expect(body).to eq(status_payload.merge(success: "RFID sign in"))
      expect(session[:user_id]).to be_nil
    end

    it "lets a guest sign the same user out again" do
      tap_card
      tap_card
      expect(body).to eq(status_payload.merge(success: "RFID sign out"))
      expect(LabSession.where(user: owner).active).to be_empty
    end

    # WART(D-EQ02): response to an unauthenticated tap discloses membership/safety-sheet state of the card owner
    it "returns membership, fundamentals and consent state of the card owner to a guest" do
      tap_card
      expect(body.keys).to match_array(%i[success has_membership has_shop_fundamentals signed_consent_form])
    end

    # WART(D-EQ03): any guest can create PiReader rows (unbounded) by posting arbitrary MAC addresses and TapBoxLog rows with arbitrary card numbers
    it "creates an unlinked PiReader and TapBoxLog rows for an unknown mac, but no Rfid" do
      expect {
        post rfid_card_number_path, params: { rfid: "BRANDNEW1", mac_address: "aa:bb:cc:dd:ee:ff" }, as: :json
      }.to change(PiReader, :count).by(1).and change(TapBoxLog, :count).by(3)
      expect(Rfid.find_by(card_number: "BRANDNEW1")).to be_nil
      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to eq(new_rfid: "Error, missing space_id or mac_address param")
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

    it "accepts space_id instead of mac_address and ignores an unknown space_id in favour of the mac" do
      post rfid_card_number_path, params: { rfid: rfid.card_number, space_id: space.id }, as: :json
      expect(body[:success]).to eq("RFID sign in")
      post rfid_card_number_path, params: { rfid: rfid.card_number, space_id: 0, mac_address: pi_reader.pi_mac_address }, as: :json
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

    # WART(D-EQ05): CardTapJob needs a "Faculty membership" tier; without it the job raises, the failure is logged to TapBoxLog and no modal is broadcast
    it "logs a card_tap_job_failure and broadcasts nothing when the Faculty membership tier is missing" do
      expect {
        expect { perform_enqueued_jobs { tap_card } }.not_to have_broadcasted_to("space_event_#{space.id}")
      }.to change { TapBoxLog.where(event_type: TapBoxLog::ERROR).count }.by(1)
      expect(TapBoxLog.where(event_type: TapBoxLog::ERROR).last.details["reason"]).to eq("card_tap_job_failure")
      expect(response).to have_http_status(:not_found)
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

    # WART(D-EQ04): a JSON tap without an rfid key is wrapped by ParamsWrapper (controller is named rfid) so params[:rfid] is a hash and the action 500s
    it "raises a 500 for a JSON tap with no rfid key (params wrapper turns params[:rfid] into a hash)" do
      post rfid_card_number_path, params: { mac_address: pi_reader.pi_mac_address }, as: :json
      expect(response).to have_http_status(:internal_server_error)
    end

    it "rejects a blank card number (form-encoded) and logs an invalid_rfid error" do
      expect {
        post rfid_card_number_path, params: { mac_address: pi_reader.pi_mac_address }
      }.not_to change(Rfid, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to eq(new_rfid: "Error, requires rfid param")
      expect(TapBoxLog.where(event_type: TapBoxLog::ERROR).last.details["reason"]).to eq("invalid_rfid")
    end

    it "rejects a tap without space_id or mac_address and logs no_space" do
      post rfid_card_number_path, params: { rfid: rfid.card_number }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to eq(new_rfid: "Error, missing space_id or mac_address param")
      expect(TapBoxLog.where(event_type: TapBoxLog::ERROR).last.details["reason"]).to eq("no_space")
    end

    it "registers an unknown reader mac without a space and logs it" do
      post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: "de:ad:be:ef:00:01" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(PiReader.find_by(pi_mac_address: "de:ad:be:ef:00:01")).to have_attributes(space_id: nil)
      expect(TapBoxLog.where(event_type: TapBoxLog::INFO).pluck(:message)).to include(a_string_matching(/New Pi reader registered/))
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
end
