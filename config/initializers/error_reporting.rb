# frozen_string_literal: true

# Forwards Rails.error reports to Airbrake. airbrake 13 / airbrake-ruby 6 do not
# subscribe to the Rails error reporter themselves, so without this every
# Rails.error.report (rescued-and-reported failures: cable disconnects, upload
# sniffing, the SAML certificate guard, the /api/v1 500 handler, ...) went
# nowhere in production.
#
# * Does nothing when Airbrake is not configured (no credentials: test, dev).
# * Never raises: reporting must not turn a handled error into a failure.
# * Errors that Airbrake's own Rack and ActiveJob integrations already catch
#   (unhandled ones re-raised through the framework) are skipped, not sent twice.
# * Values still pass through the Airbrake blocklist (config/initializers/airbrake.rb).
class AirbrakeErrorSubscriber
  ALREADY_COVERED_SOURCES = %w[application.action_dispatch active_job.].freeze

  def report(error, handled:, severity:, context:, source: nil)
    return unless Airbrake.configured?
    return if !handled && ALREADY_COVERED_SOURCES.any? { |prefix| source.to_s.start_with?(prefix) }

    Airbrake.notify(error, context.to_h.merge(handled: handled, severity: severity, source: source))
  rescue StandardError => e
    Rails.logger.warn("AirbrakeErrorSubscriber failed: #{e.class}: #{e.message}")
  end
end

Rails.error.subscribe(AirbrakeErrorSubscriber.new)
