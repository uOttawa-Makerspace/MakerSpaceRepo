# frozen_string_literal: true

require "rails_helper"

# Shadowing shifts, sub space bookings and events all reach Google Calendar as the same service account:
# the key from the credentials, the calendar scope, acting as the volunteer address, with a token fetched.
RSpec.describe "Google Calendar service account" do
  let(:google) { Rails.application.credentials[Rails.env.to_sym][:google] }
  let(:creds) { instance_double(Google::Auth::ServiceAccountCredentials, "sub=": nil, fetch_access_token!: true) }
  let(:key_sent) { {} }

  before do
    allow(GoogleCalendar::EventPublisher).to receive(:authorizer).and_call_original
    allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds) do |json_key_io:, **options|
      key_sent.merge!(JSON.parse(json_key_io.read), options.transform_keys(&:to_s))
      creds
    end
  end

  [ShadowingHour, SubSpaceBooking, GoogleCalendar::EventPublisher].each do |owner|
    it "#{owner}.authorizer signs in with the credentials' key and fetches a token" do
      expect(owner.authorizer).to be(creds)

      expect(key_sent.except("scope", "default_connection")).to eq(
        google.slice(:private_key, :client_email, :project_id, :private_key_id, :type).to_h.transform_keys(&:to_s)
      )
      expect(key_sent["scope"]).to eq("https://www.googleapis.com/auth/calendar")
      expect(key_sent["default_connection"]).to be_a(Faraday::Connection)
      expect(creds).to have_received(:sub=).with("volunteer@makerepo.com")
      expect(creds).to have_received(:fetch_access_token!)
    end
  end
end
