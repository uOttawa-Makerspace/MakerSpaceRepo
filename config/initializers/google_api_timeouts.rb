# frozen_string_literal: true

require "google/apis/options"
require "faraday"

# Bounds the waits on Google. Without it a Google Calendar call, or the service account's token fetch, that never
# answers waits forever, holding whatever the caller holds: a job slot, and for a shadowing shift the row lock its
# event is created under. Google Calendar answers in well under a second, so 10 seconds to connect and 30 to read
# leave a slow day alone and still give a stuck call up. A timeout is a transient error
# (GoogleCalendar::EventJob::TRANSIENT_ERRORS), so the jobs retry it. Only a bound is added: no retry or other
# behaviour of the clients changes.
module GoogleApiTimeouts
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 30

  # The connection the service accounts' token fetches use (passed as default_connection to
  # Google::Auth::ServiceAccountCredentials.make_creds). Only those fetches use it: Faraday's own defaults, which
  # other libraries share, are left alone.
  def self.token_connection
    Faraday.new(request: { open_timeout: OPEN_TIMEOUT, timeout: READ_TIMEOUT })
  end
end

# The Google API clients (Calendar) read these defaults when a service is created.
Google::Apis::ClientOptions.default.open_timeout_sec = GoogleApiTimeouts::OPEN_TIMEOUT
Google::Apis::ClientOptions.default.read_timeout_sec = GoogleApiTimeouts::READ_TIMEOUT
