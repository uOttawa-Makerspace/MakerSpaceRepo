# frozen_string_literal: true

require "google/apis/calendar_v3"
require "signet/oauth_2/client"
require "faraday"

module GoogleCalendar
  # Shared failure handling of the jobs that write Events to Google Calendar. Transient errors (Google server
  # errors, rate limits, access-token failures, network failures and timeouts) are retried with a growing delay; once the attempts run
  # out, and for any other Google error (a permanent refusal), the error is reported and the job ends.
  class EventJob < ApplicationJob
    queue_as :default

    TRANSIENT_ERRORS = [
      Google::Apis::ServerError, Google::Apis::RateLimitError, Google::Apis::TransmissionError,
      Timeout::Error, Net::OpenTimeout, Net::ReadTimeout,
      # Fetching the access token happens before any Google request and fails with its own errors.
      Signet::AuthorizationError, Signet::RemoteServerError, Signet::UnexpectedStatusError,
      Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError,
      SocketError, OpenSSL::SSL::SSLError, Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT
    ].freeze
    ATTEMPTS = 5

    # Handlers declared later are matched first, so the retry rule has to come after the catch-all.
    rescue_from(Google::Apis::Error) { |error| report_failure(error) }
    retry_on(*TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: ATTEMPTS) do |job, error|
      job.report_failure(error)
    end

    def report_failure(error)
      Rails.error.report(error, handled: true, context: { job: self.class.name, **failure_context })
    end

    private

    def failure_context
      {}
    end
  end
end
