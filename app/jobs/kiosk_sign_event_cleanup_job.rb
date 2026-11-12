class KioskSignEventCleanupJob < ApplicationJob
  queue_as :default

  def perform
    count = KioskSignEvent.purge_old!
    Rails.logger.info("[KioskSignEventCleanupJob] Purged #{count} old kiosk sign-in log rows")
  end
end
