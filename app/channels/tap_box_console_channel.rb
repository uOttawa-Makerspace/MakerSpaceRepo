# Thin channel used only for connection status indicator on the console page.
# Content is delivered via Turbo Streams.
class TapBoxConsoleChannel < ApplicationCable::Channel
  def subscribed
    if current_user&.staff?
      stream_from "tap_box_console_status"
    else
      reject
    end
  end

  def unsubscribed; end
end