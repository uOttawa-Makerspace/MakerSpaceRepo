class GoogleCalendarController < ApplicationController
  skip_before_action :verify_authenticity_token

  def webhook
    channel_id  = request.headers["X-Goog-Channel-Id"]
    resource_id = request.headers["X-Goog-Resource-Id"]
    state       = request.headers["X-Goog-Resource-State"]

    return head :ok if state == "sync"

    unless GoogleCalendarChannel.valid_channel?(channel_id, resource_id)
      logger.warn "[GCAL] Unknown channel #{channel_id}"
      return head :unauthorized
    end

    GoogleCalendarSyncJob.perform_later
    head :ok
  end
end