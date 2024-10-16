# frozen_string_literal: true

namespace :reports do
  desc "Send CDEL Report to an email. Email then redirects attachments to sharepoint folder"
  task send_cdel_report_to_sharepoint: :environment do
    MsrMailer.send_cdel_monthly_report("avendett@uottawa.ca").deliver_now
  end
end
