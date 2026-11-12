# frozen_string_literal: true

require "google/apis/options"
require "faraday"

# Bounds every wait on Google. Without it a Google call (or the service account's token fetch) that never answers
# waits forever, holding whatever the caller holds: a job slot, and for a shadowing shift the row lock its event is
# created under. Google Calendar answers in well under a second, so 10 seconds to connect and 30 to read leave a
# slow day alone and still give a stuck call up. A timeout is a transient error (GoogleCalendar::EventJob::TRANSIENT_ERRORS),
# so the jobs retry it. Only a bound is added: no retry or other behaviour of the clients changes.
module GoogleApiTimeouts
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 30
end

# Google API clients (Calendar) read these defaults when a service is created.
Google::Apis::ClientOptions.default.open_timeout_sec = GoogleApiTimeouts::OPEN_TIMEOUT
Google::Apis::ClientOptions.default.read_timeout_sec = GoogleApiTimeouts::READ_TIMEOUT

# The service account's token fetch goes through Faraday's default connection, which Google's auth library uses
# when it is given none. Nothing else in the app uses Faraday directly.
Faraday.default_connection_options = { request: { open_timeout: GoogleApiTimeouts::OPEN_TIMEOUT, timeout: GoogleApiTimeouts::READ_TIMEOUT } }
