# Checks with uOEng whether the user who tapped is an engineering student, then
# grants or revokes the faculty membership and pushes the popup for staff with
# the resulting membership details. A timeout, refused connection or 5xx answer
# is retried a few times; an answer that says no (or cannot be used) is not.
# Running the check again only repeats the same grant or revoke, so a retry never
# duplicates a membership. The popup is sent once: when the check completes, or
# when the retries run out.
class MembershipCheckJob < ApplicationJob
  UpstreamUnavailable = Class.new(StandardError)

  queue_as :default
  # One check per user at a time, so two taps never grant or revoke together
  limits_concurrency to: 1, key: ->(rfid, _space_id) { rfid.user_id }, duration: 1.minutes

  # Any other failure is logged for the tap box console, then left to fail
  # normally so it shows in the queue dashboard.
  rescue_from(StandardError) do |error|
    rfid, space_id = arguments
    log_failure(rfid, Space.find_by(id: space_id), error)
    raise error
  end
  # Declared after the catch-all, which Rails tries last: a tap whose card was
  # deleted while the job waited is dropped, with nothing left to log.
  discard_on ActiveJob::DeserializationError
  retry_on UpstreamUnavailable, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.give_up(error)
  end

  def perform(rfid, space_id)
    check_membership(rfid, Space.find_by(id: space_id))
    StaffDashboardChannel.send_tap_in(rfid.user, space_id)
  end

  # Called when the retries run out: record it, and still tell staff about the
  # tap, with the membership state as it is stored.
  def give_up(error)
    rfid, space_id = arguments
    log_failure(rfid, Space.find_by(id: space_id), error)
    StaffDashboardChannel.send_tap_in(rfid.user, space_id)
  end

  private

  def check_membership(rfid, space)
    result = rfid.user.validate_uoeng_membership(card_number: rfid.card_number, space: space)
    raise UpstreamUnavailable, "uOEng could not be reached" if result == :unavailable
  rescue ActiveRecord::RecordNotFound => e
    # the "Faculty membership" tier is missing. Log it, but the tap is already
    # persisted, so staff still get their popup.
    log_failure(rfid, space, e)
  end

  def log_failure(rfid, space, error)
    TapBoxLog.log_card_tap_job_failure(user: rfid.user, card_number: rfid.card_number, space: space, exception: error)
  end
end
