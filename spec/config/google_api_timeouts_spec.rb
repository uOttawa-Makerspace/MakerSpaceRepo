# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Google API timeouts" do
  it "bounds the Google API clients' connect and read waits" do
    options = Google::Apis::ClientOptions.default
    expect([options.open_timeout_sec, options.read_timeout_sec]).to eq([10, 30])
    expect(Google::Apis::CalendarV3::CalendarService.new.client_options).to have_attributes(open_timeout_sec: 10, read_timeout_sec: 30)
  end

  it "bounds the token fetch's connection, and leaves Faraday's shared defaults alone" do
    expect(GoogleApiTimeouts.token_connection.options).to have_attributes(open_timeout: 10, timeout: 30)
    expect(Faraday.default_connection_options.request.to_h.compact).to eq({})
    expect(Faraday.default_connection.options.timeout).to be_nil
  end

  it "hands that connection to the service accounts' credentials" do
    key = OpenSSL::PKey::RSA.new(2048).to_pem
    json = { type: "service_account", client_email: "a@b.iam.gserviceaccount.com", private_key: key, project_id: "p", private_key_id: "k" }.to_json
    creds = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(json), scope: "s", default_connection: GoogleApiTimeouts.token_connection
    )
    expect(creds.send(:build_default_connection).options).to have_attributes(open_timeout: 10, timeout: 30)
  end

  it "counts a timeout as a transient error, which the jobs retry" do
    expect(GoogleCalendar::EventJob::TRANSIENT_ERRORS).to include(Faraday::TimeoutError, Net::OpenTimeout, Net::ReadTimeout, Timeout::Error)
  end
end
