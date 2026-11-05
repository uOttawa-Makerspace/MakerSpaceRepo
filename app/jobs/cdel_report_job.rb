# frozen_string_literal: true

# Mails last month's CDEL reports to the inbox whose Power Automate flow files the attachments in SharePoint
# (config/recurring.yml, the 1st of each month; also `rake reports:send_cdel_report_to_sharepoint`).
class CdelReportJob < ApplicationJob
  queue_as :default

  RECIPIENT = "avendett@uottawa.ca"

  def perform
    MsrMailer.send_cdel_monthly_report(RECIPIENT).deliver_now
  end
end
