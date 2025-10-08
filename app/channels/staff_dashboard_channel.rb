class StaffDashboardChannel <  ApplicationCable::Channel
    def subscribed
      stream_for "space_event"
    end
end
