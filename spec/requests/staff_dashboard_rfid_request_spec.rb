# frozen_string_literal: true

require "rails_helper"

# PUT /staff_dashboard/link_rfid and /unlink_rfid (rows 10 and 11 of
# the frontend API inventory: the React app sends JSON
# {card_number, user_id} / {card_number} and ignores the body; the HTML profile
# page uses the redirect + flash).
RSpec.describe "Staff dashboard RFID link/unlink", type: :request do
  include StaffDashboardSpecHelpers

  let(:space_a) { create(:space) }
  let(:space_b) { create(:space) }
  let!(:reader_a) { create(:pi_reader, space: space_a) }
  let!(:reader_a2) { create(:pi_reader, space: space_a) }
  let!(:reader_b) { create(:pi_reader, space: space_b) }
  let(:owner) { create(:user, :regular_user) }
  let!(:card) { create(:rfid, user: owner, mac_address: "aa:aa:aa:aa:aa:aa") }
  let(:staff) { sign_in_as(:staff, space: space_a) }

  describe "PUT /staff_dashboard/link_rfid" do
    let!(:unlinked) { create(:rfid, user: nil, mac_address: reader_a.pi_mac_address) }
    let(:newcomer) { create(:user, :regular_user) }

    it "links the card to the user and answers {status: ok} (JSON)" do
      staff
      put staff_dashboard_link_rfid_path, params: { card_number: unlinked.card_number, user_id: newcomer.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(body).to eq("status" => "ok")
      expect(unlinked.reload.user_id).to eq(newcomer.id)
      # nothing else about the card changes
      expect(unlinked.mac_address).to eq(reader_a.pi_mac_address)
    end

    it "html: redirects back with the success notice" do
      staff
      put staff_dashboard_link_rfid_path, params: { card_number: unlinked.card_number, user_id: newcomer.id }, headers: { "HTTP_REFERER" => "http://www.example.com/anywhere" }
      expect(response).to redirect_to("http://www.example.com/anywhere")
      expect(flash[:notice]).to eq("RFID linked successfully")
      expect(unlinked.reload.user_id).to eq(newcomer.id)
    end

    it "without user_id (card_number present) changes nothing and still says ok" do
      staff
      put staff_dashboard_link_rfid_path, params: { card_number: unlinked.card_number }, as: :json
      expect(body).to eq("status" => "ok")
      expect(unlinked.reload.user_id).to be_nil
    end

    it "without card_number (user_id present) changes nothing and still says ok" do
      staff
      other = create(:user, :regular_user)
      put staff_dashboard_link_rfid_path, params: { user_id: other.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(body).to eq("status" => "ok")
      expect(Rfid.where(user_id: other.id)).to be_empty
      expect(unlinked.reload.user_id).to be_nil
      expect(card.reload.user_id).to eq(owner.id)
    end

    it "refuses a regular user (redirect to root) and leaves the card alone" do
      sign_in_as(:regular)
      put staff_dashboard_link_rfid_path, params: { card_number: unlinked.card_number, user_id: owner.id }, as: :json
      expect(response).to redirect_to(root_path)
      expect(unlinked.reload.user_id).to be_nil
    end

    it "refuses a guest (redirect to login) and leaves the card alone" do
      put staff_dashboard_link_rfid_path, params: { card_number: unlinked.card_number, user_id: owner.id }, as: :json
      expect(response).to have_http_status(:found)
      expect(response.location).to start_with("http://www.example.com/login")
      expect(unlinked.reload.user_id).to be_nil
    end

    it "creates and links a card no reader ever saw (JSON)" do
      staff
      expect do
        put staff_dashboard_link_rfid_path, params: { card_number: "phone-scanned-1", user_id: newcomer.id }, as: :json
      end.to change(Rfid, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(body).to eq("status" => "ok")
      created = Rfid.find_by!(card_number: "phone-scanned-1")
      expect(created.user_id).to eq(newcomer.id)
      expect(created.mac_address).to be_nil
    end

    it "creates and links an unknown card (html)" do
      staff
      put staff_dashboard_link_rfid_path, params: { card_number: "phone-scanned-2", user_id: newcomer.id }, headers: { "HTTP_REFERER" => "http://www.example.com/anywhere" }
      expect(flash[:notice]).to eq("RFID linked successfully")
      expect(Rfid.find_by!(card_number: "phone-scanned-2").user_id).to eq(newcomer.id)
    end

    it "refuses a card held by another user, with the reason (JSON), changing nothing" do
      staff
      other = create(:user, :regular_user)
      put staff_dashboard_link_rfid_path, params: { card_number: card.card_number, user_id: other.id }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to eq("status" => "error", "error" => "is already linked to another user")
      expect(card.reload.user_id).to eq(owner.id)
    end

    it "refuses a card held by another user, with the reason (html flash)" do
      staff
      other = create(:user, :regular_user)
      put staff_dashboard_link_rfid_path, params: { card_number: card.card_number, user_id: other.id }, headers: { "HTTP_REFERER" => "http://www.example.com/anywhere" }
      expect(response).to redirect_to("http://www.example.com/anywhere")
      expect(flash[:alert]).to include("is already linked to another user")
      expect(flash[:notice]).to be_nil
      expect(card.reload.user_id).to eq(owner.id)
    end

    it "refuses a user who already has a card, with the reason, and links nothing" do
      staff
      put staff_dashboard_link_rfid_path, params: { card_number: unlinked.card_number, user_id: owner.id }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to eq("status" => "error", "error" => "user already has a card; unlink it first")
      expect(unlinked.reload.user_id).to be_nil
      expect(Rfid.where(user_id: owner.id).pluck(:id)).to eq([card.id])
    end

    it "an unknown user_id is a 404 {status: error}, the card stays unlinked" do
      staff
      put staff_dashboard_link_rfid_path, params: { card_number: unlinked.card_number, user_id: 99_999_999 }, as: :json
      expect(response).to have_http_status(:not_found)
      expect(body["status"]).to eq("error")
      expect(unlinked.reload.user_id).to be_nil
    end

    it "an unknown user_id (html) flashes an alert" do
      staff
      put staff_dashboard_link_rfid_path, params: { card_number: unlinked.card_number, user_id: 99_999_999 }, headers: { "HTTP_REFERER" => "http://www.example.com/anywhere" }
      expect(response).to redirect_to("http://www.example.com/anywhere")
      expect(flash[:alert]).to be_present
    end

    it "an invalid card_number (too long) is refused with 422" do
      staff
      put staff_dashboard_link_rfid_path, params: { card_number: "x" * 65, user_id: owner.id }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(body["status"]).to eq("error")
    end
  end

  describe "PUT /staff_dashboard/unlink_rfid" do
    it "clears the owner and answers {status: ok} (JSON)" do
      staff
      put staff_dashboard_unlink_rfid_path, params: { card_number: card.card_number }, as: :json
      expect(response).to have_http_status(:ok)
      expect(body).to eq("status" => "ok")
      expect(card.reload.user_id).to be_nil
    end

    it "html: redirects back with the success notice" do
      staff
      put staff_dashboard_unlink_rfid_path, params: { card_number: card.card_number }, headers: { "HTTP_REFERER" => "http://www.example.com/anywhere" }
      expect(response).to redirect_to("http://www.example.com/anywhere")
      expect(flash[:notice]).to eq("RFID unlinked successfully")
    end

    it "points the card's mac_address at the first reader of the space the STAFF MEMBER last signed in to, not the card owner's space" do
      # the source of the new mac is @user.location, i.e. the signed-in
      # STAFF member's last lab session's space (User#location), not the card owner's. The
      # owner here was last in space B, yet the card is re-homed to space A's first reader.
      sign_in_session(owner, space_b, sign_out_in: 1.hour)
      sign_in_session(staff, space_a, sign_out_in: 1.hour)

      put staff_dashboard_unlink_rfid_path, params: { card_number: card.card_number }, as: :json

      expect(card.reload.user_id).to be_nil
      expect(card.mac_address).to eq(reader_a.pi_mac_address)
      expect(card.mac_address).not_to eq(reader_a2.pi_mac_address)
      expect(card.mac_address).not_to eq(reader_b.pi_mac_address)
    end

    it "keeps the card's mac_address when the staff member has never signed in to a space" do
      staff
      expect(staff.reload.location).to eq("no sign in yet")

      put staff_dashboard_unlink_rfid_path, params: { card_number: card.card_number }, as: :json

      expect(card.reload.user_id).to be_nil
      expect(card.mac_address).to eq("aa:aa:aa:aa:aa:aa")
    end

    it "keeps the mac when the staff member's last-session space has no reader" do
      empty_space = create(:space)
      sign_in_session(staff, empty_space, sign_out_in: 1.hour)

      put staff_dashboard_unlink_rfid_path, params: { card_number: card.card_number }, as: :json

      expect(body).to eq("status" => "ok")
      expect(card.reload.mac_address).to eq("aa:aa:aa:aa:aa:aa")
    end

    it "re-homes the card by the staff member's last SESSION, which can differ from the space whose unset list the staff member sees" do
      # get_unset_rfids lists by @user.space (the assigned space) while
      # unlink_rfid re-homes by @user.location (last lab session). Staff assigned to B who last
      # signed in at A unlinks a card, and it does not appear in staff B's unset list.
      staff.update!(space: space_b)
      sign_in_session(staff, space_a, sign_out_in: 1.hour)

      put staff_dashboard_unlink_rfid_path, params: { card_number: card.card_number }, as: :json
      expect(card.reload.mac_address).to eq(reader_a.pi_mac_address)

      get rfid_get_unset_rfids_path
      expect(json).to eq([])
    end

    it "makes the unlinked card show up in the staff member's own space's unset list when both agree" do
      sign_in_session(staff, space_a, sign_out_in: 1.hour)

      put staff_dashboard_unlink_rfid_path, params: { card_number: card.card_number }, as: :json

      get rfid_get_unset_rfids_path
      expect(json.map { |c| c["cardNumber"] }).to eq([card.card_number])
    end

    it "without card_number changes nothing and still says ok" do
      staff
      put staff_dashboard_unlink_rfid_path, as: :json
      expect(body).to eq("status" => "ok")
      expect(card.reload.user_id).to eq(owner.id)
    end

    it "refuses a regular user and leaves the card linked" do
      sign_in_as(:regular)
      put staff_dashboard_unlink_rfid_path, params: { card_number: card.card_number }, as: :json
      expect(response).to redirect_to(root_path)
      expect(card.reload.user_id).to eq(owner.id)
    end

    it "an unknown card_number is a 500 (NoMethodError on nil)" do
      # same nil dereference as link_rfid.
      staff
      put staff_dashboard_unlink_rfid_path, params: { card_number: "no-such-card" }, as: :json
      expect(response).to have_http_status(:internal_server_error)
      expect(exception_class).to eq("NoMethodError")
      expect(card.reload.user_id).to eq(owner.id)
    end
  end
end
