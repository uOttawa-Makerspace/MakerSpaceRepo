# frozen_string_literal: true

# Every minute (config/recurring.yml): hands out the stored orders that are due (ProcessedOrder.dispatch_due), the
# new ones the webhook could not queue, the retries whose backoff has passed and the ones whose lease expired
# because a job died, marks failed the ones whose every attempt is spent, and reports the orders nothing has
# dispatched for hours (ProcessedOrder.report_stranded).
class DispatchDueOrdersJob < ApplicationJob
  queue_as :default

  # Raised only to be reported (Rails.error.report).
  class StrandedOrder < StandardError; end

  MAX_ROUNDS = 50

  # A backlog of more than ProcessedOrder::BATCH due orders is worked through in rounds, so it is not left to age into
  # a stranded report.
  def perform(now: Time.current)
    # Spent orders are marked failed once per run: handing out does not spend an attempt, so the rounds cannot make
    # more of them.
    ProcessedOrder.fail_exhausted(now: now)
    MAX_ROUNDS.times do
      break if ProcessedOrder.dispatch_due(now: now, skip_fail_exhausted: true).size < ProcessedOrder::BATCH
    end
    ProcessedOrder.report_stranded(now: now)
  end
end
