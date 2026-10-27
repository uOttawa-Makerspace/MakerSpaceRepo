require "rails_helper"

# Chunk 15: Admin::PiReadersController#update (AdminAreaController: non-admins,
# guests included, are redirected to "/" silently, no flash).
RSpec.describe "Admin pi readers", type: :request do
  let(:pi_reader) { create(:pi_reader) }
  let(:space) { create(:space) }
  let(:params) { { id: pi_reader.id, pi_reader_params: { space_id: space.id, pi_location: "Bench 4" } } }

  %i[guest regular staff volunteer].each do |role|
    it "redirects a #{role} to / without updating" do
      sign_in_as(role)
      patch admin_pi_reader_path(pi_reader), params: params
      expect(response).to redirect_to("/")
      expect(pi_reader.reload.pi_location).to eq("Room Location")
    end
  end

  it "updates space and location for an admin and redirects back with a notice" do
    sign_in_as(:admin)
    patch admin_pi_reader_path(pi_reader), params: params, headers: { "HTTP_REFERER" => admin_keys_url }
    expect(response).to redirect_to(admin_keys_url)
    expect(flash[:notice]).to eq("Updated successfully")
    expect(pi_reader.reload).to have_attributes(space_id: space.id, pi_location: "Bench 4")
  end

  it "falls back to root without a referer" do
    sign_in_as(:admin)
    patch admin_pi_reader_path(pi_reader), params: params
    expect(response).to redirect_to(root_path)
  end

  it "ignores unpermitted attributes such as the mac address" do
    sign_in_as(:admin)
    patch admin_pi_reader_path(pi_reader), params: { id: pi_reader.id, pi_reader_params: { pi_mac_address: "zz", pi_location: "x" } }
    expect(pi_reader.reload.pi_mac_address).not_to eq("zz")
  end

  it "raises RecordNotFound (404) for an unknown reader" do
    sign_in_as(:admin)
    patch admin_pi_reader_path(0), params: params
    expect(response).to have_http_status(:not_found)
  end

  it "redirects to root with the ParameterMissing message when pi_reader_params is missing" do
    sign_in_as(:admin)
    patch admin_pi_reader_path(pi_reader), params: { foo: 1 }
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to match(/pi_reader_params/)
  end

  # D-EQ03: readers no longer self-register on their first tap, so admins register them here
  describe "POST /admin/pi_readers (register a reader)" do
    let(:create_params) { { pi_reader_params: { pi_mac_address: "aa:bb:cc:00:11:22", space_id: space.id, pi_location: "Door" } } }

    %i[guest regular staff volunteer].each do |role|
      it "redirects a #{role} to / without creating a reader" do
        sign_in_as(role)
        expect { post admin_pi_readers_path, params: create_params }.not_to change(PiReader, :count)
        expect(response).to redirect_to("/")
      end
    end

    it "lets an admin register a reader with its space and location" do
      sign_in_as(:admin)
      expect { post admin_pi_readers_path, params: create_params, headers: { "HTTP_REFERER" => admin_keys_url } }.to change(PiReader, :count).by(1)
      expect(response).to redirect_to(admin_keys_url)
      expect(flash[:notice]).to eq("Reader registered")
      expect(PiReader.last).to have_attributes(pi_mac_address: "aa:bb:cc:00:11:22", space_id: space.id, pi_location: "Door")
    end

    it "refuses a duplicate or blank mac address with an alert" do
      sign_in_as(:admin)
      existing = create(:pi_reader)
      expect do
        post admin_pi_readers_path, params: { pi_reader_params: { pi_mac_address: existing.pi_mac_address } }
        expect(flash[:alert]).to match(/Pi mac address has already been taken/)
        post admin_pi_readers_path, params: { pi_reader_params: { pi_mac_address: "" } }
        expect(flash[:alert]).to match(/Pi mac address This field is required/)
      end.not_to change(PiReader, :count)
    end
  end

  describe "recently seen unregistered readers on the space edit page" do
    it "lists distinct unregistered macs seen in the last 7 days with a one-click register button, and registering works" do
      sign_in_as(:admin)
      TapBoxLog.log_unknown_reader(mac_address: "de:ad:be:ef:00:01")
      travel_to(3.days.from_now) { TapBoxLog.log_unknown_reader(mac_address: "de:ad:be:ef:00:01") }
      old = TapBoxLog.log_unknown_reader(mac_address: "de:ad:be:ef:00:09")
      old.update_column(:created_at, 8.days.ago)
      create(:pi_reader, pi_mac_address: "de:ad:be:ef:00:05")
      TapBoxLog.log_unknown_reader(mac_address: "de:ad:be:ef:00:05") # already registered: not offered again

      get edit_admin_space_path(space)
      expect(response.body).to include("Recently seen unregistered readers")
      expect(response.body.scan("de:ad:be:ef:00:01").size).to eq(2) # once as text, once in the register button's hidden field
      expect(response.body).not_to include("de:ad:be:ef:00:09")
      expect(response.body).not_to include("de:ad:be:ef:00:05") # registered (to another space): not offered

      post admin_pi_readers_path, params: { pi_reader_params: { pi_mac_address: "de:ad:be:ef:00:01", space_id: space.id } }
      expect(PiReader.find_by_mac("de:ad:be:ef:00:01")).to have_attributes(space_id: space.id)
      get edit_admin_space_path(space)
      expect(response.body.scan("de:ad:be:ef:00:01").size).to eq(1) # now only in the registered readers table
    end

    it "does not show the section to non-admins" do
      sign_in_as(:staff)
      get edit_admin_space_path(space)
      expect(response).to redirect_to("/")
    end
  end

  it "shows the register-reader form on the space edit page for an admin" do
    sign_in_as(:admin)
    get edit_admin_space_path(space)
    expect(response.body).to include("Register a new RFID Reader").and include(admin_pi_readers_path)
  end
end
