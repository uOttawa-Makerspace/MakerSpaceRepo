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

  # readers do not self-register on their first tap, so admins register them here
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

    it "adopts a legacy space-less row with the same normalized mac: assigns space/location, normalizes the mac, no duplicate" do
      sign_in_as(:admin)
      legacy = create(:pi_reader, space: nil, pi_location: "old")
      legacy.update_column(:pi_mac_address, "AA-BB-CC-00-11-22")
      expect {
        post admin_pi_readers_path, params: { pi_reader_params: { pi_mac_address: "aa:bb:cc:00:11:22", space_id: space.id, pi_location: "Door" } }
      }.not_to change(PiReader, :count)
      expect(flash[:notice]).to eq("Reader registered")
      expect(legacy.reload).to have_attributes(pi_mac_address: "aa:bb:cc:00:11:22", space_id: space.id, pi_location: "Door")
    end

    it "refuses to adopt a legacy row with a blank or non-existent space: error flash, no success notice, nothing changes" do
      sign_in_as(:admin)
      legacy = create(:pi_reader, space: nil, pi_location: "old")
      legacy.update_column(:pi_mac_address, "AA-BB-CC-00-11-22")
      [{}, { space_id: "" }, { space_id: 0 }, { space_id: "abc" }].each do |space_param|
        post admin_pi_readers_path, params: { pi_reader_params: { pi_mac_address: "aa:bb:cc:00:11:22", pi_location: "Door" }.merge(space_param) }
        expect(flash[:alert]).to eq("Space must exist")
        expect(flash[:notice]).to be_nil
        expect(legacy.reload).to have_attributes(pi_mac_address: "AA-BB-CC-00-11-22", space_id: nil, pi_location: "old")
      end
    end

    it "keeps the legacy location when none is given, and still refuses a mac already registered to a space" do
      sign_in_as(:admin)
      legacy = create(:pi_reader, space: nil, pi_location: "old")
      post admin_pi_readers_path, params: { pi_reader_params: { pi_mac_address: legacy.pi_mac_address, space_id: space.id } }
      expect(legacy.reload).to have_attributes(space_id: space.id, pi_location: "old")
    end

    it "refuses a mac already registered to a space as an error, not a success" do
      sign_in_as(:admin)
      legacy = create(:pi_reader, space: space)
      expect {
        post admin_pi_readers_path, params: { pi_reader_params: { pi_mac_address: legacy.pi_mac_address.upcase, space_id: create(:space).id } }
      }.not_to change(PiReader, :count)
      expect(flash[:alert]).to match(/already been taken/)
      expect(flash[:notice]).to be_nil
      expect(legacy.reload.space_id).to eq(space.id)
    end

    it "refuses a 70-character identifier and one with a tab in the middle: alert, nothing created" do
      sign_in_as(:admin)
      expect do
        post admin_pi_readers_path, params: { pi_reader_params: { pi_mac_address: "a" * 70, space_id: space.id } }
        expect(flash[:alert]).to match(/at most 64 characters/)
        post admin_pi_readers_path, params: { pi_reader_params: { pi_mac_address: "aa:bb\tcc", space_id: space.id } }
        expect(flash[:alert]).to match(/at most 64 characters/)
      end.not_to change(PiReader, :count)
    end

    it "still adopts a legacy row whose identifier is a bounded short one" do
      sign_in_as(:admin)
      legacy = create(:pi_reader, space: nil, pi_mac_address: "ab12")
      legacy.update_column(:pi_mac_address, "ab12")
      post admin_pi_readers_path, params: { pi_reader_params: { pi_mac_address: "ab12", space_id: space.id } }
      expect(flash[:notice]).to eq("Reader registered")
      expect(legacy.reload.space_id).to eq(space.id)
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

    it "shows only the 50 most recently seen macs plus a count of the rest, with one registered-macs query" do
      sign_in_as(:admin)
      now = Time.current
      rows = (0...60).map do |i|
        { event_type: "warning", message: TapBoxLog::UNKNOWN_READER_MESSAGE, mac_address: "de:ad:be:ef:%02x:%02x" % [i / 256, i % 256],
          created_at: now - i.minutes, updated_at: now - i.minutes, details: {} }
      end
      TapBoxLog.insert_all(rows)
      create(:pi_reader, pi_mac_address: "de:ad:be:ef:00:00").tap { |r| r.update_column(:pi_mac_address, "DE:AD:BE:EF:00:00") } # newest, registered: filtered out

      sql = []
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| sql << payload[:sql] }
      get edit_admin_space_path(space)
      ActiveSupport::Notifications.unsubscribe(sub)

      shown = response.body.scan(/de:ad:be:ef:00:[0-9a-f]{2}/).uniq.size
      expect(shown).to eq(50)
      expect(response.body).to include("de:ad:be:ef:00:01").and include("de:ad:be:ef:00:32")
      expect(response.body).not_to include("de:ad:be:ef:00:33")
      expect(response.body).to include("...and 9 more not shown.")
      expect(sql.grep(/lower\(replace/)).to be_empty
    end

    it "does not show the section to non-admins" do
      sign_in_as(:staff)
      get edit_admin_space_path(space)
      expect(response).to redirect_to("/")
    end
  end

  it "keeps space-less (legacy self-registered) readers in the Unassociated list so an admin can associate them" do
    sign_in_as(:admin)
    legacy = create(:pi_reader, space: nil)
    get edit_admin_space_path(space)
    expect(response.body).to include("Unassociated RFID Readers").and include(legacy.pi_mac_address)
    patch admin_pi_reader_path(legacy), params: { pi_reader_params: { space_id: space.id } }
    expect(legacy.reload.space_id).to eq(space.id)
  end

  it "names the reader's space in the staff unlinked-cards menu even when the card's mac differs in case (A10 round 3)" do
    sign_in_as(:staff)
    reader = create(:pi_reader, space: space)
    reader.update_column(:pi_mac_address, reader.pi_mac_address.upcase)
    create(:rfid, user: nil, mac_address: reader.pi_mac_address.downcase)
    get user_path(create(:user, :regular_user).username)
    expect(response.body).to include("Tapped at #{space.name}")
  end

  it "shows the register-reader form on the space edit page for an admin" do
    sign_in_as(:admin)
    get edit_admin_space_path(space)
    expect(response.body).to include("Register a new RFID Reader").and include(admin_pi_readers_path)
  end
end
