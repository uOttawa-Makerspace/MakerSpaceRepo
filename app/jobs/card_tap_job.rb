# frozen_string_literal: true

# Runs when a user taps their card on the tap box. Push a popup modal to staff
# dashboard with membership details
class CardTapJob < ApplicationJob
  queue_as :default
  # Network call to faculty can take time, make sure we don't process double
  # taps out of order. Only one job per space can run
  limits_concurrency to: 1, key: ->(_rfid, space_id) { space_id }, duration: 1.minutes

  def perform(rfid, space_id)
    # Update faculty membership
    space = Space.find_by(id: space_id)

    rfid.user.validate_uoeng_membership(
      card_number: rfid.card_number,
      space: space
    )

    # Push notification to staff dashboard
    StaffDashboardChannel.send_tap_in(rfid.user, space_id)
  rescue => e
    TapBoxLog.log!(
      event_type: TapBoxLog::ERROR,
      message: "CardTapJob failed for #{rfid.user&.name}: #{e.message}",
      card_number: rfid.card_number,
      user: rfid.user,
      space: Space.find_by(id: space_id),
      details: {
        reason: "card_tap_job_failure",
        exception_class: e.class.name,
        backtrace: e.backtrace&.first(5)
      }
    )
    raise
  end
end