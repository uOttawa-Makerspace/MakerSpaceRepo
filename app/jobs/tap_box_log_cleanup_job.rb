class TapBoxLogCleanupJob < ApplicationJob
  queue_as :default

  def perform
    count = TapBoxLog.purge_old!(days: 30)
    Rails.logger.info("[TapBoxLogCleanupJob] Purged #{count} old log entries")
  end
end