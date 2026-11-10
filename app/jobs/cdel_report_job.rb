# frozen_string_literal: true

# Mails a month's CDEL reports to the inbox whose Power Automate flow files the attachments in SharePoint
# (config/recurring.yml, the 1st of each month, for the month just ended; also
# `rake "reports:send_cdel_report_to_sharepoint[2026-08]"`). Without a month it is last month, in the app time zone.
#
# A month is mailed once: the run records it in Setting (SENT_KEY_PREFIX + month) in the same transaction as the
# delivery, so a failed delivery leaves nothing recorded and the next run sends it, while a second run (a rerun,
# a retry, another worker) waits for the first one's row lock and then finds the month already sent. +force+
# mails a month that was already sent (rake: FORCE=1).
class CdelReportJob < ApplicationJob
  queue_as :default

  RECIPIENT = "avendett@uottawa.ca"
  SENT_KEY_PREFIX = "cdel_report_sent:"

  class InvalidMonth < ArgumentError; end

  # Refuse a bad month when the job is queued, not hours later in the worker.
  before_enqueue { self.class.parse_month(self.class.month_argument(arguments)) }

  # The month as "YYYY-MM", given by keyword (month: "2026-08") or as the first argument ("2026-08"); nil for
  # last month.
  def perform(positional_month = nil, month: nil, force: false)
    first_day = self.class.parse_month(month || positional_month)
    reported_month = first_day || Time.zone.today.prev_month.beginning_of_month
    Setting.transaction do
      next unless Setting.claim("#{SENT_KEY_PREFIX}#{reported_month.strftime("%Y-%m")}", "sent", force: force)

      MsrMailer.send_cdel_monthly_report(RECIPIENT, month: reported_month).deliver_now
    end
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
end
