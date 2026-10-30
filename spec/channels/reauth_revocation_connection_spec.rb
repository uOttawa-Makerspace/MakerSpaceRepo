# frozen_string_literal: true

require "rails_helper"

# The websocket handshake resolves its user through the same authenticators as the
# controllers, so the one token_version bump made by RateLimitCounter.increment_revoking
# (re-auth exhaustion) refuses a reconnect with the old cookie session or JWT.
RSpec.describe ApplicationCable::Connection do
  include ActionCable::Connection::TestCase::Behavior

  tests ApplicationCable::Connection

  let!(:user) { create(:user, :regular_user) }
  let(:session_data) { { user_id: user.id, token_version: user.token_version, expires_at: 1.hour.from_now } }

  def exhaust!(version)
    results = Array.new(6) do
      RateLimitCounter.increment_revoking("reauth/#{user.id}/#{version}", user_id: user.id, token_version: version,
                                                                          max: 5, expires_in: 15.minutes)
    end
    expect(results.map(&:last).compact.size).to eq(1)
  end

  it "accepts the cookie session and the JWT before, and refuses both after the revocation" do
    token = user.token
    connect session: session_data
    expect(connection.current_user).to eq(user)
    connect params: { token: token }
    expect(connection.current_user).to eq(user)

    exhaust!(user.token_version)

    expect { connect session: session_data }.to have_rejected_connection
    expect { connect params: { token: token } }.to have_rejected_connection
  end
end
