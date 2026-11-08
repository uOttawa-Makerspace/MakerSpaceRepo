# frozen_string_literal: true

# Every 5 minutes (config/recurring.yml): mails the maintenance address about failed and overdue background jobs
# it has not reported yet (JobAlert).
class JobAlertJob < ApplicationJob
  queue_as :default

  def perform
    count = JobAlert.new.run
    Rails.logger.info("[JobAlertJob] Reported #{count} jobs") if count.positive?
  end
end
