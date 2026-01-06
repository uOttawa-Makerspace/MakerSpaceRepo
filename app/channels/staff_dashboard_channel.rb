# Communicates with the staff dashboard via a websocket connection. Used to
# update the tables with any user activity
class StaffDashboardChannel < ApplicationCable::Channel
  # include Turbo::StreamsHelper

  def subscribed
    # stream_from takes a string as an argument
    # stream_for takes an object or a record
    stream_from "space_event_#{params[:space_id]}"
  end

  # RFID tap job finished executing and validated membership
  # Notify staff dashboard with a modal
  def self.send_tap_in(user, space_id)
    # Send HTML table update
    broadcast_table_updates(space_id)

    # Send modal notification
    ActionCable.server.broadcast(
      "space_event_#{space_id}",
      {
        add_user: {
          username: user.username,
          name: user.name,
          id: user.id,
          email: user.email,
          certification:
            Certification
              .joins(:training)
              .where(user_id: user.id)
              .pluck('trainings.name_en'),
          membership: user.has_active_membership?,
          expiration_date: user.active_membership&.end_date&.to_date,
          is_student: user.student?,
          signed_sheet: user.walk_in_safety_sheets.any?
        }
      }
    )
  end

  def self.send_tap_out(user, space_id)
    broadcast_table_updates(space_id)
  end

  def self.broadcast_table_updates(space_id)
    space = Space.find(space_id)

    Turbo::StreamsChannel.broadcast_render_to(
      'signed_in_table',
      partial: 'staff_dashboard/table_broadcast',
      locals: {
        space: space,
        signed_in_users:
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
        signed_out_users: space.recently_signed_out_users
      }
    )
  end
end
