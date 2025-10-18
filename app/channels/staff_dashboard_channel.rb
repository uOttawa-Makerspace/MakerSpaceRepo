# Communicates with the staff dashboard via a websocket connection. Used to
# update the tables with any user activity
class StaffDashboardChannel < ApplicationCable::Channel
  def subscribed
    stream_from 'space_event'
  end

  # RFID tap job finished executing and validated membership
  # Notify staff dashboard with a modal
  def self.send_tap_in(user, space_id)
    Turbo::StreamsChannel.broadcast_update_to(
      'signed_in_table',
      target: 'table-js-signed-in',
      partial: 'staff_dashboard/space_activity_row',
      locals: {
        space: Space.find(16)
      },
      collection:
        User
          .strict_loading
          .includes(certifications: { training_session: %i[training user] })
          .includes(:lab_sessions)
          .where(
            lab_sessions: {
              sign_out_time: Time.zone.now..,
              space: space_id
            }
          ),
    )
  end

  def self.send_tap_out(user, space_id)
    Turbo::StreamsChannel.broadcast_update_to(
      'signed_in_table',
      target: 'table-js-signed-in',
      partial: 'staff_dashboard/space_activity_row',
      locals: {
        space: Space.find(space_id)
      },
      collection:
        User
          .strict_loading
          .includes(certifications: { training_session: %i[training user] })
          .includes(:lab_sessions)
          .where(
            lab_sessions: {
              sign_out_time: Time.zone.now..,
              space: space_id
            }
          ),
    )
  end
end
