# Runs when a user taps their card on the tap box. Push a popup modal to staff
# dashboard with membership details
class CardTapJob < ApplicationJob
  queue_as :default
  # Network call to faculty can take time, make sure we don't process double
  # taps out of order. Only one job per space can run
  limits_concurrency to: 1, key: ->(_rfid, space_id) { space_id }, duration: 1.minutes

  def perform(rfid, space_id)
    # Update faculty membership
    rfid.user.validate_uoeng_membership

    # Push notification to staff dashboard
    StaffDashboardChannel.send_tap_in(rfid.user, space_id)
  end
end
