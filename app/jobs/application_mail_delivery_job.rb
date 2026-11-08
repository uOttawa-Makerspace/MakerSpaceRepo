# frozen_string_literal: true

# Delivers every mail queued with deliver_later. A mail whose record was deleted before the job ran (for
# example a chat message removed right after it was sent) has nothing left to say, so the job is dropped and
# logged instead of being left as a failed job. Any other error still fails the job as usual.
class ApplicationMailDeliveryJob < ActionMailer::MailDeliveryJob
  discard_on ActiveJob::DeserializationError do |job, error|
    Rails.logger.warn("Discarded #{job.class.name} #{job.job_id}: #{error.message}")
  end
end
