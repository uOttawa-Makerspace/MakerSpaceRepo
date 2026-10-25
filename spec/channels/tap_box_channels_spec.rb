require "rails_helper"

# Chunk 15: ActionCable boundary for the tap box.
# ApplicationCable::Connection#connect identifies EVERY connection as
# `rand(100)` (the cookie-checking find_verified_user is dead code), so there
# is no connection authentication at all.
RSpec.describe "Tap box ActionCable channels" do
  describe ApplicationCable::Connection, type: :channel do
    # WART(D-EQ30): ApplicationCable::Connection accepts every websocket and sets current_user to a random Integer; nothing authenticates cable subscribers
    it "accepts a connection with no cookies and identifies it as an Integer" do
      connect "/cable"
      expect(connection.current_user).to be_a(Integer)
      expect(connection.current_user).to be_between(0, 99)
    end
  end

  describe StaffDashboardChannel, type: :channel do
    # WART(D-EQ31): StaffDashboardChannel streams "space_event_<space_id>" to any subscriber (unauthenticated, any space_id), exposing tapped users' name, email and certifications
    it "subscribes any connection to the raw space_event stream for the requested space" do
      stub_connection current_user: 7
      subscribe(space_id: 3)
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("space_event_3")
    end

    it "subscribes even without a space id (stream space_event_)" do
      stub_connection current_user: nil
      subscribe
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("space_event_")
    end
  end

  describe TapBoxConsoleChannel, type: :channel do
    it "streams tap_box_console_status for a staff user" do
      stub_connection current_user: create(:user, :staff)
      subscribe
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("tap_box_console_status")
    end

    it "rejects a regular user" do
      stub_connection current_user: create(:user, :regular_user)
      subscribe
      expect(subscription).to be_rejected
    end

    it "rejects a missing user" do
      stub_connection current_user: nil
      subscribe
      expect(subscription).to be_rejected
    end

    # WART(D-EQ08): with the real connection (current_user is a random Integer) subscribe raises NoMethodError on Integer#staff?, so the console status channel never confirms, even for staff
    it "raises for the Integer identity the real connection assigns" do
      stub_connection current_user: 42
      expect { subscribe }.to raise_error(NoMethodError, /staff\?/)
    end
  end
end
