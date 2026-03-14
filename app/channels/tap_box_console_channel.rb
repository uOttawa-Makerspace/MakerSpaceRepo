class TapBoxConsoleChannel < ApplicationCable::Channel
  def subscribed
    if current_user&.staff?
      stream_from "tap_box_console"
    else
      reject
    end
  end

  def unsubscribed
    # cleanup
  end

  def self.broadcast_log(log)
    ActionCable.server.broadcast("tap_box_console", log.as_broadcast)
  end
end