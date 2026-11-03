# frozen_string_literal: true

require "rails_helper"

RSpec.describe CdelReportJob, type: :job do
  include ActiveJob::TestHelper

  it "mails last month's CDEL report to its recipient, with the three CSV attachments" do
    ActionMailer::Base.deliveries.clear
    described_class.perform_now

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([described_class::RECIPIENT])
    expect(mail.subject).to start_with("CDEL Reports from ")
    expect(mail.attachments.map(&:filename)).to match_array(
      [/CEED_visitors_dump/, /CEED_certifications_dump/, /CEED_new_users_dump/].map { |re| a_string_matching(re) }
    )
  end

  it "is what the rake task runs" do
    require "rake"
    Rails.application.load_tasks unless Rake::Task.task_defined?("reports:send_cdel_report_to_sharepoint")
    Rake::Task["reports:send_cdel_report_to_sharepoint"].reenable
    expect(described_class).to receive(:perform_now)
    Rake::Task["reports:send_cdel_report_to_sharepoint"].invoke
  end
end
