# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Google API timeouts" do
  it "bounds the Google API clients' connect and read waits" do
    options = Google::Apis::ClientOptions.default
    expect([options.open_timeout_sec, options.read_timeout_sec]).to eq([10, 30])
    expect(Google::Apis::CalendarV3::CalendarService.new.client_options).to have_attributes(open_timeout_sec: 10, read_timeout_sec: 30)
  end

  it "bounds the token fetch's default connection" do
    expect(Faraday.default_connection.options).to have_attributes(open_timeout: 10, timeout: 30)
  end

  it "counts a timeout as a transient error, which the jobs retry" do
    expect(GoogleCalendar::EventJob::TRANSIENT_ERRORS).to include(Faraday::TimeoutError, Net::OpenTimeout, Net::ReadTimeout, Timeout::Error)
  end
end
