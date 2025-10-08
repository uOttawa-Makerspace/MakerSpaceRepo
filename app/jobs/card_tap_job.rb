# Runs when a user taps their card on the tap box. Push a popup modal to staff
# dashboard with membership details
class CardTapJob < ApplicationJob
  queue_as :default

  def perform(rfid)
    # Update faculty membership
    rfid.user.validate_uoeng_membership

    # Push notification to staff dashboard
  end
end
