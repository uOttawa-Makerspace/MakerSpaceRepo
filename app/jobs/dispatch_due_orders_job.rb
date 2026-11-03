# frozen_string_literal: true

# Every minute (config/recurring.yml): hands out the stored orders that are due (ProcessedOrder.dispatch_due), the
# new ones the webhook could not queue, the retries whose backoff has passed and the ones whose lease expired
# because a job died, and reports the orders nothing has dispatched for hours (ProcessedOrder.report_stranded).
class DispatchDueOrdersJob < ApplicationJob
  queue_as :default

  # Raised only to be reported (Rails.error.report).
  class StrandedOrder < StandardError; end

  def perform(now: Time.current)
    ProcessedOrder.dispatch_due(now: now)
    ProcessedOrder.report_stranded(now: now)
  end
end
