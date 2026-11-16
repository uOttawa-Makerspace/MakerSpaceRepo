# frozen_string_literal: true

# Reports an error a model, service or job has rescued and carried on from: it is logged and sent to Rails.error
# (Airbrake). There is no request here, so this is the counterpart of ErrorReporting#report_unexpected for code that
# runs outside a controller. The caller still decides what happens next (a documented fallback, or a re-raise).
module HandledError
  def self.report(error, severity: :error, **context)
    Rails.logger.error("[#{context[:source] || 'handled error'}] #{error.class}: #{error.message}")
    Rails.error.report(error, handled: true, severity: severity, context: context)
  end
end
