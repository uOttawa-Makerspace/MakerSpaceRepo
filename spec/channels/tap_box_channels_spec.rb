require "rails_helper"

# Chunk 15: ActionCable boundary for the tap box.
# ApplicationCable::Connection#connect identifies EVERY connection as
# `rand(100)` (the cookie-checking find_verified_user is dead code), so there
# is no connection authentication at all.
RSpec.describe "Tap box ActionCable channels" do
  describe ApplicationCable::Connection, type: :channel do
    # FIXED(D-EQ30): the connection identifies the user from the session cookie and rejects everyone else
    it "identifies the session's user" do
      user = create(:user, :staff)
      connect "/cable", session: { user_id: user.id }
      expect(connection.current_user).to eq(user)
    end

    it "identifies a regular user too (channels decide what they may subscribe to)" do
      user = create(:user, :regular_user)
      connect "/cable", session: { user_id: user.id }
      expect(connection.current_user).to eq(user)
    end

    it "rejects a connection with no session" do
      expect { connect "/cable" }.to have_rejected_connection
    end

    it "rejects a session whose user no longer exists" do
      expect { connect "/cable", session: { user_id: 0 } }.to have_rejected_connection
    end

    # A12 rules (lib/jwt_authenticator.rb), shared with the HTTP side
    describe "session rules" do
      let(:user) { create(:user, :staff) }

      it "rejects a session whose token_version no longer matches (password changed/reset, admin lock)" do
        stale = { user_id: user.id, token_version: user.token_version }
        user.update_columns(token_version: user.token_version + 1)
        expect { connect "/cable", session: stale }.to have_rejected_connection
        expect { connect "/cable", session: stale.merge(token_version: user.token_version) }.not_to have_rejected_connection
      end

      it "treats a session without token_version as version 0" do
        expect { connect "/cable", session: { user_id: user.id } }.not_to have_rejected_connection
        user.update_columns(token_version: 1)
        expect { connect "/cable", session: { user_id: user.id } }.to have_rejected_connection
      end

      it "rejects a deactivated or soft-deleted user" do
        user.update_columns(active: false)
        expect { connect "/cable", session: { user_id: user.id, token_version: user.token_version } }.to have_rejected_connection
        user.update_columns(active: true, deleted: true)
        expect { connect "/cable", session: { user_id: user.id, token_version: user.token_version } }.to have_rejected_connection
      end

      it "rejects an idle-expired session and accepts one inside the window" do
        expect { connect "/cable", session: { user_id: user.id, expires_at: 1.minute.ago } }.to have_rejected_connection
        expect { connect "/cable", session: { user_id: user.id, expires_at: 1.hour.from_now } }.not_to have_rejected_connection
      end
    end

    describe "Bearer JWT" do
      let(:user) { create(:user, :staff) }

      it "identifies the user from the Authorization header" do
        connect "/cable", headers: { "Authorization" => "Bearer #{user.token}" }
        expect(connection.current_user).to eq(user)
      end

      it "identifies the user from a token query param" do
        connect "/cable?token=#{user.token}"
        expect(connection.current_user).to eq(user)
      end

      it "rejects garbage, a revoked (old token_version) token and an inactive user's token" do
        old = user.token
        expect { connect "/cable", headers: { "Authorization" => "Bearer nope" } }.to have_rejected_connection
        expect { connect "/cable?token=nope" }.to have_rejected_connection
        user.update_columns(token_version: user.token_version + 1)
        expect { connect "/cable", headers: { "Authorization" => "Bearer #{old}" } }.to have_rejected_connection
        expect { connect "/cable", headers: { "Authorization" => "Bearer #{user.token}" } }.not_to have_rejected_connection
        user.update_columns(active: false)
        expect { connect "/cable", headers: { "Authorization" => "Bearer #{user.token}" } }.to have_rejected_connection
      end
    end
  end

  describe StaffDashboardChannel, type: :channel do
    # FIXED(D-EQ31): only staff/admin may stream "space_event_<space_id>" (tapped users' name, email, certifications)
    %i[staff admin].each do |role|
      it "streams space_event_<id> to a #{role}" do
        stub_connection current_user: create(:user, role)
        subscribe(space_id: 3)
        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_from("space_event_3")
      end
    end

    %i[regular_user volunteer_with_dev_program].each do |trait|
      it "rejects a #{trait}" do
        stub_connection current_user: create(:user, trait)
        subscribe(space_id: 3)
        expect(subscription).to be_rejected
      end
    end

    it "rejects a missing user and a non-user identity" do
      stub_connection current_user: nil
      subscribe(space_id: 3)
      expect(subscription).to be_rejected
    end

    it "rejects a guest User.new" do
      stub_connection current_user: User.new
      subscribe(space_id: 3)
      expect(subscription).to be_rejected
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

    # FIXED(D-EQ08): with a real (authenticated) connection the console channel confirms for staff
    it "confirms for the staff user the real connection identifies" do
      staff = create(:user, :staff)
      stub_connection current_user: staff
      subscribe
      expect(subscription).to be_confirmed
    end
  end
end
