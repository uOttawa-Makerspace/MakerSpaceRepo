# frozen_string_literal: true

namespace :reports do
  desc "Send the CDEL Report (last month, or the given YYYY-MM) to an email. Email then redirects attachments to sharepoint folder. A month already sent is skipped unless FORCE=1"
  task :send_cdel_report_to_sharepoint, [:month] => :environment do |_task, args|
    CdelReportJob.perform_now(month: args[:month], force: ENV["FORCE"] == "1")
  rescue CdelReportJob::InvalidMonth => e
    abort e.message
  end
end
