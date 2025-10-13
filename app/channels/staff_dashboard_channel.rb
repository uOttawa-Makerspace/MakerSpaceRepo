# Communicates with the staff dashboard via a websocket connection. Used to
# update the tables with any user activity
class StaffDashboardChannel < ApplicationCable::Channel
  def subscribed
    stream_from 'space_event'
  end

  # RFID tap job finished executing and validated membership
  # Notify staff dashboard with a modal
  def self.send_tap_in(user)
    ActionCable.server.broadcast 'space_event',
                                 {
                                   add_user: {
                                     username: user.username,
                                     name: user.name,
                                     id: user.id,
                                     email: user.email,
                                     #certification: user.certifications.pluck(:name_en),
                                     membership: user.has_active_membership?,
                                     expiration_date:
                                       user
                                         .active_membership
                                         &.end_date
                                         &.to_date,
                                     is_student: user.student?,
                                     signed_sheet:
                                       user.walk_in_safety_sheets.any?
                                   }
                                 }
  end

  def self.send_tap_out(user)
    ActionCable.server.broadcast 'space_event', { remove_user: user.id }
  end
end
