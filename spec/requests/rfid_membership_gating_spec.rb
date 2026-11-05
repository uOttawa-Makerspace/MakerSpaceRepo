# frozen_string_literal: true

require "rails_helper"

# Does the kiosk / RFID path refuse or flag a user whose membership has lapsed?
#
# Answer (pinned here): it does NOT refuse. RfidController#card_number never looks
# at memberships: a registered reader + a linked card always yields "RFID sign in"
# and a LabSession, whatever the owner's membership state. CardTapJob only (a)
# auto-grants/revokes the *Faculty* membership for engineering users and (b) pushes
# the staff-dashboard modal, whose payload carries `membership: <bool>` and the
# expiration date for STAFF to read. The signed-in/out tables and
# GET /staff_dashboard.json `membership_status` also only display the state.
# Nothing in this repo denies entry (the door/reader firmware only reads `success`).
RSpec.describe "RFID tap and membership state (not enforced)", type: :request do
  include ActiveJob::TestHelper
  include_context "with test cable adapter"

  let(:space) { create(:space) }
  let(:pi_reader) { create(:pi_reader, space: space) }
  let(:owner) { create(:user, :regular_user) }
  let!(:rfid) { create(:rfid, user: owner, mac_address: pi_reader.pi_mac_address) }
  let!(:tier) { create(:membership_tier, duration: 30, internal_price: 1, external_price: 2) }

  before do
    create(:membership_tier, title_en: "Faculty membership", title_fr: "Adhesion de la faculte",
                             internal_price: 0, external_price: 0, duration: 4.months.to_i)
  end

  def tap_card
    post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: pi_reader.pi_mac_address }, as: :json
  end

  def modal_payload
    payload = nil
    allow(ActionCable.server).to receive(:broadcast).and_wrap_original do |original, stream, message, *rest|
      payload = message if stream == "space_event_#{space.id}" && message.is_a?(Hash) && message[:add_user]
      original.call(stream, message, *rest)
    end
    perform_enqueued_jobs { yield }
    payload&.dig(:add_user)
  end

  shared_examples "signs in anyway, flagging the state only to staff" do |expected_flag|
    it "answers RFID sign in with a LabSession and no membership rejection" do
      expect { tap_card }.to change { LabSession.where(user: owner, space: space).active.count }.from(0).to(1)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("success" => "RFID sign in")
    end

    it "tells staff via the modal payload (membership: #{expected_flag}) after CardTapJob" do
      add_user = modal_payload { tap_card }
      expect(response).to have_http_status(:ok)
      expect(add_user[:id]).to eq(owner.id)
      expect(add_user[:membership]).to be(expected_flag)
    end
  end

  context "no membership at all" do
    include_examples "signs in anyway, flagging the state only to staff", false

    it "has no expiration date in the modal" do
      expect(modal_payload { tap_card }[:expiration_date]).to be_nil
    end
  end

  context "an expired paid membership (lapsed)" do
    before { create(:membership, user: owner, membership_tier: tier, status: "paid", start_date: 60.days.ago, end_date: 1.day.ago) }

    include_examples "signs in anyway, flagging the state only to staff", false

    it "shows no expiration date (expired memberships are not 'active')" do
      expect(modal_payload { tap_card }[:expiration_date]).to be_nil
    end
  end

  context "a pending (unpaid) membership" do
    before { create(:membership, user: owner, membership_tier: tier, status: "pending") }

    include_examples "signs in anyway, flagging the state only to staff", false
  end

  context "a revoked membership with time left" do
    before { create(:membership, user: owner, membership_tier: tier, status: "revoked") }

    include_examples "signs in anyway, flagging the state only to staff", false
  end

  context "an active paid membership" do
    let(:ends) { 10.days.from_now.change(usec: 0) }

    before { create(:membership, user: owner, membership_tier: tier, status: "paid", end_date: ends) }

    include_examples "signs in anyway, flagging the state only to staff", true

    it "carries the expiration date in the modal" do
      expect(modal_payload { tap_card }[:expiration_date]).to eq(ends.to_date)
    end
  end

  it "lapsed vs active produce the same tap response and session (membership is not part of the decision)" do
    lapsed = create(:user, :regular_user)
    create(:membership, user: lapsed, membership_tier: tier, status: "paid", start_date: 60.days.ago, end_date: 1.day.ago)
    lapsed_card = create(:rfid, user: lapsed, mac_address: pi_reader.pi_mac_address)
    post rfid_card_number_path, params: { rfid: lapsed_card.card_number, mac_address: pi_reader.pi_mac_address }, as: :json
    lapsed_body = [response.status, response.parsed_body]

    create(:membership, user: owner, membership_tier: tier, status: "paid")
    tap_card
    expect([response.status, response.parsed_body]).to eq(lapsed_body)
    expect(LabSession.active.pluck(:user_id)).to match_array([lapsed.id, owner.id])
  end

  describe "staff dashboard JSON" do
    # the JSON calls has_active_membership? per signed-in user (a memberships query each),
    # so with 2+ users Bullet (raising under CI=1) flags an N+1 and the request 500s; skipped here.
    it "reports membership_status false for a signed-in user with a lapsed membership, without removing them", skip_bullet: true do
      create(:membership, user: owner, membership_tier: tier, status: "paid", start_date: 60.days.ago, end_date: 1.day.ago)
      active_user = create(:user, :regular_user)
      create(:membership, user: active_user, membership_tier: tier, status: "paid")
      [owner, active_user].each { |u| create(:lab_session, space: space, user: u, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now) }
      sign_in_as(:staff, space: space)

      get staff_dashboard_index_path, as: :json

      users = response.parsed_body["space_users"].index_by { |u| u["id"] }
      expect(users.keys).to match_array([owner.id, active_user.id])
      expect(users[owner.id]["membership_status"]).to be(false)
      expect(users[active_user.id]["membership_status"]).to be(true)
    end
  end
end
