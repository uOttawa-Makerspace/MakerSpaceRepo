# frozen_string_literal: true

require "rails_helper"

# Contract: doc/api/v1/rfid.md
RSpec.describe "/api/v1 RFID", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  include_context "with test cable adapter"

  let(:json_headers) { { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" } }
  let(:admin) { create(:user, :admin) }
  let(:staff) { create(:user, :staff) }
  let(:regular) { create(:user) }
  let(:space_a) { create(:space) }
  let(:space_b) { create(:space) }
  let!(:reader_a) { create(:pi_reader, space: space_a) }
  let!(:reader_b) { create(:pi_reader, space: space_b) }
  let(:owner) { create(:user, :regular_user) }

  def body = response.parsed_body
  def error = body["error"]
  def auth(user) = { "Authorization" => "Bearer #{ApiAccessToken.issue(user).first}" }
  def api_get(path, as: nil, params: {}) = get(path, params: params, headers: json_headers.merge(as ? auth(as) : {}))
  def api_send(verb, path, payload = nil, as: nil) = public_send(verb, path, params: payload&.to_json, headers: json_headers.merge(as ? auth(as) : {}))

  describe "GET /api/v1/rfid_cards?linked=false" do
    let!(:card_a) { create(:rfid, user: nil, mac_address: reader_a.pi_mac_address, updated_at: 2.minutes.ago) }
    let!(:newer_a) { create(:rfid, user: nil, mac_address: reader_a.pi_mac_address, updated_at: 1.minute.ago) }
    let!(:card_b) { create(:rfid, user: nil, mac_address: reader_b.pi_mac_address) }
    let!(:linked) { create(:rfid, user: owner, mac_address: reader_a.pi_mac_address) }
    let!(:phone_card) { create(:rfid, user: nil, mac_address: nil) }

    it "401s a guest and 403s a regular user" do
      api_get "/api/v1/rfid_cards", params: { linked: "false" }
      expect(response).to have_http_status(:unauthorized)
      api_get "/api/v1/rfid_cards", as: regular, params: { linked: "false" }
      expect(response).to have_http_status(:forbidden)
    end

    it "lists the assigned space's unlinked cards, newest first, as exactly {card_number, tapped_at} (ISO 8601)" do
      staff.update_columns(space_id: space_a.id)
      api_get "/api/v1/rfid_cards", as: staff, params: { linked: "false" }
      expect(response).to have_http_status(:ok)
      expect(body.map(&:keys).uniq).to eq([%w[card_number tapped_at]])
      expect(body.map { |c| c["card_number"] }).to eq([newer_a.card_number, card_a.card_number])
      expect(body.first["tapped_at"]).to eq(newer_a.reload.updated_at.utc.iso8601)
      expect(Time.iso8601(body.first["tapped_at"])).to be_within(1.second).of(newer_a.updated_at)
    end

    it "gives the same set as the legacy get_unset_rfids, for staff and admin (every space when none is assigned)" do
      [staff, admin].each do |caller|
        api_get "/api/v1/rfid_cards", as: caller, params: { linked: "false" }
        expect(body.map { |c| c["card_number"] }).to match_array([newer_a, card_a, card_b].map(&:card_number))
      end
    end

    it "caps the list at 5" do
      6.times { create(:rfid, user: nil, mac_address: reader_a.pi_mac_address) }
      api_get "/api/v1/rfid_cards", as: admin, params: { linked: "false" }
      expect(body.size).to eq(5)
    end

    it "422s unless linked=false" do
      [{}, { linked: "true" }, { linked: "x" }].each do |params|
        api_get "/api/v1/rfid_cards", as: staff, params: params
        expect(response).to have_http_status(:unprocessable_content)
        expect(error["fields"].keys).to eq(["linked"])
      end
    end
  end

  describe "PUT /api/v1/users/:id/rfid" do
    let!(:card) { create(:rfid, user: nil, mac_address: reader_a.pi_mac_address) }

    it "401s a guest and 403s a regular user, linking nothing" do
      api_send :put, "/api/v1/users/#{owner.id}/rfid", { card_number: card.card_number }
      expect(response).to have_http_status(:unauthorized)
      api_send :put, "/api/v1/users/#{owner.id}/rfid", { card_number: card.card_number }, as: regular
      expect(response).to have_http_status(:forbidden)
      expect(card.reload.user_id).to be_nil
    end

    it "links the card to the user (staff and admin) and changes nothing else about the card" do
      [staff, admin].each do |caller|
        user = create(:user, :regular_user)
        c = create(:rfid, user: nil, mac_address: reader_a.pi_mac_address)
        api_send :put, "/api/v1/users/#{user.id}/rfid", { card_number: c.card_number }, as: caller
        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_empty
        expect(c.reload.user_id).to eq(user.id)
        expect(c.mac_address).to eq(reader_a.pi_mac_address)
      end
    end

    it "makes the card read as the user's card on their profile" do
      api_send :put, "/api/v1/users/#{owner.id}/rfid", { card_number: card.card_number }, as: staff
      api_get "/api/v1/users/#{owner.username}", as: staff
      expect(body["user"]["rfid"]).to eq("card_number" => card.card_number)
    end

    it "is a no-op for the pair that is already linked" do
      api_send :put, "/api/v1/users/#{owner.id}/rfid", { card_number: card.card_number }, as: staff
      expect { api_send :put, "/api/v1/users/#{owner.id}/rfid", { card_number: card.card_number }, as: staff }
        .not_to change { card.reload.updated_at }
      expect(response).to have_http_status(:no_content)
    end

    it "refuses a card another user holds (DEVIATION: legacy re-pointed it silently); nothing changes" do
      taken = create(:rfid, user: owner)
      thief = create(:user, :regular_user)
      api_send :put, "/api/v1/users/#{thief.id}/rfid", { card_number: taken.card_number }, as: staff
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["code"]).to eq("validation_failed")
      expect(error["fields"]["card_number"]).to eq(["is already linked to another user"])
      expect(taken.reload.user_id).to eq(owner.id)
    end

    it "refuses a user who already holds a different card (DEVIATION: legacy gave them two); they must unlink first" do
      create(:rfid, user: owner)
      api_send :put, "/api/v1/users/#{owner.id}/rfid", { card_number: card.card_number }, as: staff
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["fields"]["card_number"]).to eq(["user already has a card; unlink it first"])
      expect(card.reload.user_id).to be_nil
      expect(Rfid.where(user_id: owner.id).count).to eq(1)
    end

    it "404s an unknown card (it has to be tapped first), an unknown, deleted or non-numeric user" do
      api_send :put, "/api/v1/users/#{owner.id}/rfid", { card_number: "no-such-card" }, as: staff
      expect(response).to have_http_status(:not_found)
      expect(error["code"]).to eq("not_found")
      api_send :put, "/api/v1/users/99999999/rfid", { card_number: card.card_number }, as: staff
      expect(response).to have_http_status(:not_found)
      gone = create(:user, :regular_user)
      gone.update_columns(deleted: true)
      api_send :put, "/api/v1/users/#{gone.id}/rfid", { card_number: card.card_number }, as: staff
      expect(response).to have_http_status(:not_found)
      api_send :put, "/api/v1/users/abc/rfid", { card_number: card.card_number }, as: staff
      expect(response).to have_http_status(:not_found)
      expect(card.reload.user_id).to be_nil
    end

    it "422s a missing or non-string card_number" do
      api_send :put, "/api/v1/users/#{owner.id}/rfid", {}, as: staff
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["code"]).to eq("parameter_missing")
      api_send :put, "/api/v1/users/#{owner.id}/rfid", { card_number: { a: 1 } }, as: staff
      expect(response).to have_http_status(:unprocessable_content)
      api_send :put, "/api/v1/users/#{owner.id}/rfid", { card_number: [card.card_number] }, as: staff
      expect(response).to have_http_status(:unprocessable_content)
      expect(card.reload.user_id).to be_nil
    end
  end

  describe "DELETE /api/v1/users/:id/rfid" do
    let!(:card) { create(:rfid, user: owner, mac_address: "aa:aa:aa:aa:aa:aa") }

    it "401s a guest and 403s a regular user, unlinking nothing" do
      api_send :delete, "/api/v1/users/#{owner.id}/rfid"
      expect(response).to have_http_status(:unauthorized)
      api_send :delete, "/api/v1/users/#{owner.id}/rfid", as: regular
      expect(response).to have_http_status(:forbidden)
      expect(card.reload.user_id).to eq(owner.id)
    end

    it "unlinks the user's card (staff and admin)" do
      [staff, admin].each do |caller|
        user = create(:user, :regular_user)
        c = create(:rfid, user: user)
        api_send :delete, "/api/v1/users/#{user.id}/rfid", as: caller
        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_empty
        expect(c.reload.user_id).to be_nil
        expect(Rfid.where(id: c.id)).to exist
      end
    end

    it "keeps the card's mac when the staff member has never signed in anywhere" do
      api_send :delete, "/api/v1/users/#{owner.id}/rfid", as: staff
      expect(card.reload.mac_address).to eq("aa:aa:aa:aa:aa:aa")
    end

    it "re-homes the card to the first reader of the space the STAFF member last signed in to, like the legacy unlink_rfid" do
      create(:lab_session, user: staff, space: space_b, sign_in_time: 1.hour.ago, sign_out_time: 1.hour.from_now)
      api_send :delete, "/api/v1/users/#{owner.id}/rfid", as: staff
      expect(card.reload.mac_address).to eq(reader_b.pi_mac_address)
    end

    it "then lists the card among the unlinked taps of that space" do
      staff.update_columns(space_id: space_a.id)
      create(:lab_session, user: staff, space: space_a, sign_in_time: 1.hour.ago, sign_out_time: 1.hour.from_now)
      api_send :delete, "/api/v1/users/#{owner.id}/rfid", as: staff
      api_get "/api/v1/rfid_cards", as: staff, params: { linked: "false" }
      expect(body.map { |c| c["card_number"] }).to eq([card.card_number])
    end

    it "is a no-op 204 for a user without a card (DEVIATION: legacy 500 on an unknown card_number)" do
      other = create(:user, :regular_user)
      expect { api_send :delete, "/api/v1/users/#{other.id}/rfid", as: staff }.not_to change { Rfid.pluck(:id, :user_id).sort }
      expect(response).to have_http_status(:no_content)
    end

    it "404s an unknown or non-numeric user" do
      api_send :delete, "/api/v1/users/99999999/rfid", as: staff
      expect(response).to have_http_status(:not_found)
      api_send :delete, "/api/v1/users/abc/rfid", as: staff
      expect(response).to have_http_status(:not_found)
      expect(card.reload.user_id).to eq(owner.id)
    end
  end

  describe "POST /api/v1/rfid_taps" do
    let!(:card) { create(:rfid, user: owner, mac_address: nil) }

    def tap(payload = { card_number: card.card_number, space_id: space_a.id }, as: staff)
      api_send :post, "/api/v1/rfid_taps", payload, as: as
    end

    it "401s a guest and 403s a regular user, writing nothing" do
      expect do
        tap(as: nil)
        expect(response).to have_http_status(:unauthorized)
        tap(as: regular)
        expect(response).to have_http_status(:forbidden)
      end.not_to change { [LabSession.count, Rfid.count, TapBoxLog.count] }
    end

    it "signs the card's owner in with exactly {success: 'RFID sign in'} (staff and admin), then out" do
      [staff, admin].each do |caller|
        tap(as: caller)
        expect(response).to have_http_status(:ok)
        expect(body).to eq("success" => "RFID sign in")
        expect(LabSession.where(user: owner, space: space_a).active.count).to eq(1)
        tap(as: caller)
        expect(body).to eq("success" => "RFID sign out")
        expect(LabSession.where(user: owner).active).to be_empty
      end
    end

    it "writes the same lab session a Pi tap does (6 hours, no mac) and queues the membership check" do
      freeze_time do
        expect { tap }.to have_enqueued_job(CardTapJob)
        row = LabSession.where(user: owner).sole
        expect(row.space_id).to eq(space_a.id)
        expect(row.sign_in_time).to eq(Time.zone.now)
        expect(row.sign_out_time).to eq(Time.zone.now + 6.hours)
        expect(row.mac_address).to be_nil
      end
    end

    it "moves a user signed in elsewhere: signs them out there and in here" do
      elsewhere = create(:lab_session, user: owner, space: space_b, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
      tap
      expect(body).to eq("success" => "RFID sign in")
      expect(elsewhere.reload.sign_out_time).to be <= Time.zone.now
      expect(LabSession.where(user: owner).active.sole.space_id).to eq(space_a.id)
    end

    it "does not leak the card owner" do
      tap
      expect(response.body).not_to include(owner.email, owner.username, owner.name)
    end

    it "an unlinked known card is a 422 card_not_linked and is refreshed for the unlinked list" do
      loose = create(:rfid, user: nil, mac_address: reader_b.pi_mac_address, updated_at: 1.day.ago)
      expect { tap({ card_number: loose.card_number, space_id: space_a.id }) }.not_to change(LabSession, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["code"]).to eq("card_not_linked")
      expect(loose.reload.updated_at).to be > 1.hour.ago
    end

    it "an unknown card is stored as an unlinked card and answered 422 card_not_linked" do
      expect { tap({ card_number: "BRAND-NEW", space_id: space_a.id }) }.to change { Rfid.where(card_number: "BRAND-NEW", user_id: nil).count }.by(1)
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["code"]).to eq("card_not_linked")
      expect(LabSession.count).to eq(0)
    end

    it "404s an unknown space; 422s a missing or malformed card_number or space_id" do
      tap({ card_number: card.card_number, space_id: 0 })
      expect(response).to have_http_status(:not_found)
      tap({ card_number: card.card_number })
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["code"]).to eq("parameter_missing")
      tap({ space_id: space_a.id })
      expect(response).to have_http_status(:unprocessable_content)
      tap({ card_number: { a: 1 }, space_id: space_a.id })
      expect(response).to have_http_status(:unprocessable_content)
      tap({ card_number: card.card_number, space_id: "x" })
      expect(response).to have_http_status(:unprocessable_content)
      expect(LabSession.count).to eq(0)
    end

    it "logs the tap like the legacy endpoint" do
      expect { tap }.to change(TapBoxLog, :count)
    end

    describe "rate limit" do
      # (An unlinked card keeps the taps cheap: no lab sessions or broadcasts.)
      let(:loose) { create(:rfid, user: nil, mac_address: nil) }

      it "429s the 61st tap in a minute, per staff user, and does not count guests" do
        counts = Hash.new(0)
        allow(Api::V1::RfidTapsController.cache_store).to receive(:increment) { |key, *| counts[key] += 1 }
        61.times { tap(as: nil) }
        expect(counts).to be_empty
        60.times { tap }
        expect(response).to have_http_status(:ok)
        tap
        expect(response).to have_http_status(:too_many_requests)
        expect(error["code"]).to eq("rate_limited")
        tap(as: admin)
        expect(response).to have_http_status(:ok)
      end

      it "shares the per-user budget with the legacy staff tap on /rfid/card_number" do
        counts = Hash.new(0)
        allow(Api::V1::RfidTapsController.cache_store).to receive(:increment) { |key, *| counts[key] += 1 }
        payload = { card_number: loose.card_number, space_id: space_a.id }
        legacy = -> { post "/rfid/card_number", params: { rfid: loose.card_number, space_id: space_a.id }.to_json, headers: json_headers.merge("Authorization" => "Bearer #{staff.token}") }
        40.times { legacy.call }
        expect(response).not_to have_http_status(:too_many_requests)
        20.times { tap(payload) }
        expect(response).to have_http_status(:unprocessable_content)
        tap(payload)
        expect(response).to have_http_status(:too_many_requests)
        expect(error["code"]).to eq("rate_limited")
        legacy.call
        expect(response).to have_http_status(:too_many_requests)
        expect(counts.keys).to include("rate-limit:rfid:tap:staff:#{staff.id}", "rate-limit:rfid:tap-ip:127.0.0.1")
      end

      it "shares the per-IP budget with the legacy endpoint" do
        counts = Hash.new(0)
        allow(Api::V1::RfidTapsController.cache_store).to receive(:increment) { |key, *| counts[key] += 1 }
        counts["rate-limit:rfid:tap-ip:127.0.0.1"] = 600
        tap({ card_number: loose.card_number, space_id: space_a.id })
        expect(response).to have_http_status(:too_many_requests)
      end
    end
  end
end
