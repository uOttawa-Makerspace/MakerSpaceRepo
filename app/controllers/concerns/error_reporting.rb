# frozen_string_literal: true

# Shared pieces of the error answers: a short reference code a user can quote,
# the single place unexpected exceptions are logged and reported, and the
# translated texts built from them. The reference is the first characters of the
# request id, so it finds the request's log lines (production and staging tag
# every line with the request id) and the Airbrake notice (its context carries
# the request id and the reference). Used by ApplicationController and
# Api::V1::BaseController.
#
# Exception text is for the log and Airbrake only: it never goes into a message
# shown to a user.
module ErrorReporting
  extend ActiveSupport::Concern

  REFERENCE_LENGTH = 8
  BACKTRACE_LINES = 15

  # Views show the reference (the API controllers have no views).
  included { helper_method :error_reference if respond_to?(:helper_method) }

  private

  def error_reference
    request.request_id.to_s.first(REFERENCE_LENGTH)
  end

  # Logs the exception (class, message, top of the backtrace) with the reference and
  # sends it to Rails.error (Airbrake). `context` lands in the Airbrake notice.
  def report_unexpected(exception, **context)
    Rails.logger.error(unexpected_log_line(exception))
    Rails.error.report(
      exception,
      handled: true,
      severity: :error,
      context: context.merge(request_id: request.request_id, reference: error_reference)
    )
  end

  def unexpected_log_line(exception)
    trace = exception.backtrace&.first(BACKTRACE_LINES)&.join("\n")
    "[#{error_reference}] #{exception.class}: #{exception.message}\n#{trace}"
  end

  def unexpected_error_message
    I18n.t("errors.generic.unexpected", reference: error_reference)
  end

  # The translated sentence at `key` followed by the record's validation messages (just the sentence when there are none).
  def validation_message(record, key)
    [I18n.t(key), record.errors.full_messages.to_sentence].compact_blank.join(" ")
  end
end
