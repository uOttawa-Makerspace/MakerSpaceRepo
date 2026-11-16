# Runs when a user taps their card on the tap box. Updates the signed-in tables
# on the staff dashboard once, then hands the faculty membership check and the
# popup that reports it to MembershipCheckJob, which can be retried on its own.
class CardTapJob < ApplicationJob
  queue_as :default
  # Make sure we don't process double taps out of order. Only one job per space
  # can run
  limits_concurrency to: 1, key: ->(_rfid, space_id) { space_id }, duration: 1.minutes

  def perform(rfid, space_id)
    StaffDashboardChannel.broadcast_table_updates(space_id)
    MembershipCheckJob.perform_later(rfid, space_id)
  end
end
