# frozen_string_literal: true

require "rails_helper"

# PUT /staff_dashboard/link_rfid and /unlink_rfid (rows 10 and 11 of
# doc/refactor/frontend-api-inventory.md: the React app sends JSON
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

    it "links the card to the user and answers {status: ok} (JSON)" do
      staff
      put staff_dashboard_link_rfid_path, params: { card_number: unlinked.card_number, user_id: owner.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(body).to eq("status" => "ok")
      expect(unlinked.reload.user_id).to eq(owner.id)
      # nothing else about the card changes
      expect(unlinked.mac_address).to eq(reader_a.pi_mac_address)
    end

    it "html: redirects back with the success notice" do
      staff
      put staff_dashboard_link_rfid_path, params: { card_number: unlinked.card_number, user_id: owner.id }, headers: { "HTTP_REFERER" => "http://www.example.com/anywhere" }
      expect(response).to redirect_to("http://www.example.com/anywhere")
      expect(flash[:notice]).to eq("RFID linked successfully")
      expect(unlinked.reload.user_id).to eq(owner.id)
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

    it "an unknown card_number is a 500 (NoMethodError on nil), nothing is written" do
      # WART(D-STAFF-RFID-NIL-NEW): Rfid.find_by returns nil and `rfid.user_id=` is called on it,
      # so the React app gets an HTML 500 instead of {status: "error"}.
      staff
      expect { put staff_dashboard_link_rfid_path, params: { card_number: "no-such-card", user_id: owner.id }, as: :json }
        .not_to change { Rfid.pluck(:id, :user_id).sort }
      expect(response).to have_http_status(:internal_server_error)
      expect(exception_class).to eq("NoMethodError")
    end

    it "an unknown user_id is a 500 (foreign key violation), the card stays unlinked" do
      # WART(D-STAFF-RFID-NIL-NEW): no existence check on user_id; rfid.save hits the FK constraint.
      staff
      put staff_dashboard_link_rfid_path, params: { card_number: unlinked.card_number, user_id: 99_999_999 }, as: :json
      expect(response).to have_http_status(:internal_server_error)
      expect(exception_class).to eq("ActiveRecord::InvalidForeignKey")
      expect(unlinked.reload.user_id).to be_nil
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
      # WART(D-RFID-UNLINK-NEW): the source of the new mac is @user.location, i.e. the signed-in
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
      # WART(D-RFID-UNLINK-NEW): get_unset_rfids lists by @user.space (the assigned space) while
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
      # WART(D-STAFF-RFID-NIL-NEW): same nil dereference as link_rfid.
      staff
      put staff_dashboard_unlink_rfid_path, params: { card_number: "no-such-card" }, as: :json
      expect(response).to have_http_status(:internal_server_error)
      expect(exception_class).to eq("NoMethodError")
      expect(card.reload.user_id).to eq(owner.id)
    end
  end
end
