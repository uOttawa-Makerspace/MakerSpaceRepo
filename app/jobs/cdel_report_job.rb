# frozen_string_literal: true

# Mails a month's CDEL reports to the inbox whose Power Automate flow files the attachments in SharePoint
# (config/recurring.yml, the 1st of each month, for the month just ended; also
# `rake "reports:send_cdel_report_to_sharepoint[2026-08]"`). Without a month it is last month, in the app time zone.
#
# A month is mailed once. A run first claims the month in Setting (SENT_KEY_PREFIX + month) in a short transaction
# of its own: the value goes from empty to "claimed:<time>", and a second run (a rerun, a retry, another worker)
# that finds a claim younger than CLAIM_TIMEOUT mails nothing. The reports are generated and the mail delivered
# after that transaction has committed, and then the value becomes "sent". A run that raises hands its claim back,
# so the next run sends the month. A run killed outright leaves its claim, which turns retryable once it is older
# than CLAIM_TIMEOUT, so a month is never lost (a crash right after delivery can mail it twice). +force+ mails a
# month whatever its state (rake: FORCE=1).
class CdelReportJob < ApplicationJob
  queue_as :default

  RECIPIENT = "avendett@uottawa.ca"
  SENT_KEY_PREFIX = "cdel_report_sent:"
  CLAIM_PREFIX = "claimed:"
  CLAIM_TIMEOUT = 30.minutes

  class InvalidMonth < ArgumentError; end

  # Refuse a bad month when the job is queued, not hours later in the worker.
  before_enqueue { self.class.parse_month(self.class.month_argument(arguments)) }

  # The month as "YYYY-MM", given by keyword (month: "2026-08") or as the first argument ("2026-08"); nil for
  # last month.
  def perform(positional_month = nil, month: nil, force: false)
    first_day = self.class.parse_month(month || positional_month)
    reported_month = first_day || Time.zone.today.prev_month.beginning_of_month
    key = "#{SENT_KEY_PREFIX}#{reported_month.strftime("%Y-%m")}"
    claim = claim_month(key, force)
    return unless claim

    deliver_or_release(key, claim, reported_month)
    Setting.swap(key, claim, "sent")
  end

  def self.month_argument(arguments)
    first = arguments.first
    first.is_a?(Hash) ? first[:month] : first
  end

  # The first day of the month named by +value+ ("YYYY-MM"), or nil when there is none. Raises InvalidMonth for
  # anything else and for a month after the current one.
  def self.parse_month(value)
    return nil if value.blank?

    match = /\A(\d{4})-(0[1-9]|1[0-2])\z/.match(value.to_s)
    raise InvalidMonth, "Invalid month #{value.to_s.inspect}: use YYYY-MM, for example 2026-08" unless match

    first_day = Date.new(match[1].to_i, match[2].to_i, 1)
    if first_day > Time.zone.today.beginning_of_month
      raise InvalidMonth, "Month #{value} is in the future: use the current month or an earlier one"
    end

    first_day
  end

  private

  # The value written to claim the month, or nil when another run has it (sent, or claimed less than
  # CLAIM_TIMEOUT ago).
  def claim_month(key, force)
    claim = "#{CLAIM_PREFIX}#{Time.current.iso8601}"
    return (Setting.claim(key, claim, force: true) ? claim : nil) if force

    current = Setting.get(key)
    return claim if Setting.swap(key, nil, claim)

    claim if stale_claim?(current) && Setting.swap(key, current, claim)
  end

  def stale_claim?(value)
    value.to_s.start_with?(CLAIM_PREFIX) && Time.zone.parse(value.delete_prefix(CLAIM_PREFIX)) < CLAIM_TIMEOUT.ago
  end

  def deliver_or_release(key, claim, reported_month)
    MsrMailer.send_cdel_monthly_report(RECIPIENT, month: reported_month).deliver_now
  rescue StandardError
    Setting.swap(key, claim, nil)
    raise
  end
end
