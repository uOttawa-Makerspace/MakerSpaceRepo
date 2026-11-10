# frozen_string_literal: true

# Delivers every mail queued with deliver_later.
#
# * A mail whose record was deleted before the job ran (for example a chat message removed right after it was
#   sent) has nothing left to say, so the job is dropped and logged.
# * A network failure or a temporary SMTP refusal (a 4xx reply: server busy, try again later) is retried after the
#   waits in RETRY_WAITS (30 seconds, 2 minutes, 10 minutes, 30 minutes, 1 hour, 2 hours: 7 runs in all, about
#   4 hours), exactly as listed, with no random jitter. If the last run fails too, the error fails the job as
#   usual, so it is listed as a failed execution and mailed to the maintenance address. A job waiting for a
#   retry is a scheduled execution due in the future, which JobAlert does not report.
# * Any other error, including a permanent SMTP refusal (a 5xx reply, a rejected login, a malformed command),
#   fails the job as usual after one run: it is not retried, and it is listed as a failed execution and mailed to
#   the maintenance address, so a refused mail is never dropped silently.
class ApplicationMailDeliveryJob < ActionMailer::MailDeliveryJob
  RETRY_WAITS = [30.seconds, 2.minutes, 10.minutes, 30.minutes, 1.hour, 2.hours].freeze

  TRANSIENT_ERRORS = [
    Net::SMTPServerBusy,
    Timeout::Error, # also Net::OpenTimeout and Net::ReadTimeout
    SocketError, EOFError, OpenSSL::SSL::SSLError,
    Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::EHOSTUNREACH, Errno::EPIPE
  ].freeze

  retry_on(*TRANSIENT_ERRORS, wait: ->(executions) { RETRY_WAITS.fetch(executions - 1) },
                         attempts: RETRY_WAITS.size + 1)

  discard_on ActiveJob::DeserializationError do |job, error|
    Rails.logger.warn("Discarded #{job.class.name} #{job.job_id}: #{error.message}")
  end
end
