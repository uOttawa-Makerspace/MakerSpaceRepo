# frozen_string_literal: true

# Forwards Rails.error reports to Airbrake. airbrake 13 / airbrake-ruby 6 do not
# subscribe to the Rails error reporter themselves, so without this every
# Rails.error.report (rescued-and-reported failures: cable disconnects, upload
# sniffing, the SAML certificate guard, the /api/v1 500 handler, ...) went
# nowhere in production.
#
# * Does nothing when Airbrake is not configured (no credentials: test, dev).
# * Never raises: reporting must not turn a handled error into a failure.
# * Unhandled errors that Airbrake's own integrations already catch are skipped, not
#   sent twice: "application.action_dispatch" (the Executor middleware; Airbrake's Rack
#   middleware has the error) and "application.active_support" (the Executor.wrap that
#   runs jobs; Airbrake's ActiveJob rescue_from(Exception) has the error). Reports
#   from retry_on/discard_on ("application.active_job", report: true) are forwarded:
#   those handlers run before Airbrake's, so nothing else sends them.
# * Values still pass through the Airbrake blocklist (config/initializers/airbrake.rb).
class AirbrakeErrorSubscriber
  ALREADY_COVERED_SOURCES = %w[application.action_dispatch application.active_support].freeze

  def report(error, handled:, severity:, context:, source: nil)
    return unless Airbrake.configured?
    return if !handled && ALREADY_COVERED_SOURCES.include?(source.to_s)

    # The caller's own context[:source] (e.g. "api_v1") is kept; Rails' source goes under :rails_source.
    Airbrake.notify(error, context.to_h.merge(handled: handled, severity: severity, rails_source: source))
  rescue StandardError => e
    Rails.logger.warn("AirbrakeErrorSubscriber failed: #{e.class}: #{e.message}")
  end
end

Rails.error.subscribe(AirbrakeErrorSubscriber.new)
