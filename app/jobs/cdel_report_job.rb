# frozen_string_literal: true

# Mails a month's CDEL reports to the inbox whose Power Automate flow files the attachments in SharePoint
# (config/recurring.yml, the 1st of each month, for the month just ended; also
# `rake "reports:send_cdel_report_to_sharepoint[2026-08]"`). Without a month it is last month, in the app time zone.
class CdelReportJob < ApplicationJob
  queue_as :default

  RECIPIENT = "avendett@uottawa.ca"

  class InvalidMonth < ArgumentError; end

  # Refuse a bad month when the job is queued, not hours later in the worker.
  before_enqueue { self.class.parse_month(arguments.first&.dig(:month)) }

  # month: "YYYY-MM", or nil for last month.
  def perform(month: nil)
    MsrMailer.send_cdel_monthly_report(RECIPIENT, month: self.class.parse_month(month)).deliver_now
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
