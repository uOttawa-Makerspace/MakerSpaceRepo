class StaffDashboardChannel <  ApplicationCable::Channel
    def subscribed
      stream_from "space_event"
    end

    # RFID tap job finished executing and validated membership
    # Notify staff dashboard with a modal
    def self.send_tap(user)
      ActionCable.server.broadcast 'space_event', {user_id: user.id}
    end
end
