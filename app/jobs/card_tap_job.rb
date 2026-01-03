# Runs when a user taps their card on the tap box. Push a popup modal to staff
# dashboard with membership details
class CardTapJob < ApplicationJob
  queue_as :default

  def perform(rfid, space_id)
    # Update faculty membership
    rfid.user.validate_uoeng_membership

    # Push notification to staff dashboard
    StaffDashboardChannel.send_tap_in(rfid.user, space_id)
  end
end
