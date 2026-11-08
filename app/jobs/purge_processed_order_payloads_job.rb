# frozen_string_literal: true

# Every day (config/recurring.yml): blanks the payload of the stored orders applied more than
# ProcessedOrder::PAYLOAD_RETENTION ago (ProcessedOrder.purge_payloads!). The rows stay as the idempotency key.
class PurgeProcessedOrderPayloadsJob < ApplicationJob
  queue_as :default

  def perform
    count = ProcessedOrder.purge_payloads!
    Rails.logger.info("[PurgeProcessedOrderPayloadsJob] Blanked #{count} payloads")
  end
end
