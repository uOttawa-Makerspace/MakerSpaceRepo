class GoogleCalendarController < ApplicationController
  # Google's push notifications carry no CSRF token; the caller is authenticated by
  # the live channel id/resource id pair we registered and its token (GoogleCalendarChannel.valid_channel?).
  skip_forgery_protection

  def webhook
    channel_id  = request.headers["X-Goog-Channel-Id"]
    resource_id = request.headers["X-Goog-Resource-Id"]
    token       = request.headers["X-Goog-Channel-Token"]
    state       = request.headers["X-Goog-Resource-State"]

    return head :ok if state == "sync"

    unless GoogleCalendarChannel.valid_channel?(channel_id, resource_id, token)
      logger.warn "[GCAL] Unknown channel #{channel_id}"
      return head :unauthorized
    end

    GoogleCalendarSyncJob.perform_later
    head :ok
  end
end