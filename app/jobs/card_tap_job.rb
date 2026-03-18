# Runs when a user taps their card on the tap box. Push a popup modal to staff
# dashboard with membership details
class CardTapJob < ApplicationJob
  queue_as :default
  # Network call to faculty can take time, make sure we don't process double
  # taps out of order. Only one job per space can run
  limits_concurrency to: 1, key: ->(_rfid, space_id) { space_id }, duration: 1.minutes

  def perform(rfid, space_id)
    # Update faculty membership
    user = rfid.user
    space = Space.find_by(id: space_id)

    TapBoxLog.log!(
      event_type: TapBoxLog::MEMBERSHIP_CHECK,
      message: "Starting membership eligibility check for #{user.name}",
      card_number: rfid.card_number,
      user: user,
      space: space,
      details: {
        student_id: user.student_id,
        email: user.email,
        has_student_id: user.student_id.present?,
        has_uottawa_email: user.email&.ends_with?("@uottawa.ca")
      }
    )

    start_time = Time.current

    begin
      result = rfid.user.validate_uoeng_membership(
        card_number: rfid.card_number,
        space: space
      )
      elapsed = ((Time.current - start_time) * 1000).round(1)

      if result.nil?
        TapBoxLog.log!(
          event_type: TapBoxLog::MEMBERSHIP_CHECK,
          message: "#{user.name} is NOT engineering — faculty membership revoked",
          card_number: rfid.card_number,
          user: user,
          space: space,
          details: { elapsed_ms: elapsed, result: "not_engineering" }
        )
      else
        TapBoxLog.log!(
          event_type: TapBoxLog::MEMBERSHIP_CHECK,
          message: "#{user.name} IS engineering — faculty membership active until #{result.end_date}",
          card_number: rfid.card_number,
          user: user,
          space: space,
          details: {
            elapsed_ms: elapsed,
            result: "engineering",
            membership_id: result.id,
            end_date: result.end_date.to_s
          }
        )
      end
    rescue => e
      elapsed = ((Time.current - start_time) * 1000).round(1)

      TapBoxLog.log!(
        event_type: TapBoxLog::ERROR,
        message: "Membership check failed for #{user.name}: #{e.message}",
        card_number: rfid.card_number,
        user: user,
        space: space,
        details: {
          elapsed_ms: elapsed,
          exception_class: e.class.name,
          backtrace: e.backtrace&.first(5)
        }
      )

      raise # re-raise so Solid Queue can retry
    end

    # Push notification to staff dashboard
    StaffDashboardChannel.send_tap_in(rfid.user, space_id)
  end
end