# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe CdelReportJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { Time.find_zone("America/New_York") }

  def last_mail
    ActionMailer::Base.deliveries.last
  end

  before { ActionMailer::Base.deliveries.clear }

  it "mails last month's CDEL report to its recipient, with the three CSV attachments" do
    travel_to(zone.local(2026, 11, 1, 0, 0)) { described_class.perform_now }

    expect(last_mail.to).to eq([described_class::RECIPIENT])
    expect(last_mail.subject).to eq("CDEL Reports from 2026-10-01 to 2026-10-31")
    expect(last_mail.attachments.map(&:filename)).to match_array(
      [/CEED_visitors_dump/, /CEED_certifications_dump/, /CEED_new_users_dump/].map { |re| a_string_matching(re) }
    )
  end

  it "reports last month in the app time zone, even when UTC is already in the next month" do
    # 2026-11-01 00:30 Eastern is 04:30 UTC; 2026-10-31 23:30 Eastern is already 2026-11-01 03:30 UTC
    travel_to(zone.local(2026, 10, 31, 23, 30)) { described_class.perform_now }
    expect(last_mail.subject).to eq("CDEL Reports from 2026-09-01 to 2026-09-30")
  end

  it "reports the month it is given, with that month's dates in the attachment names" do
    travel_to(zone.local(2026, 11, 5, 12, 0)) { described_class.perform_now(month: "2026-08") }

    expect(last_mail.subject).to eq("CDEL Reports from 2026-08-01 to 2026-08-31")
    names = last_mail.attachments.map(&:filename)
    expect(names.size).to eq(3)
    expect(names).to all(include("2026-08-01").and(include("2026-08-31")))
  end

  it "takes the month as the first argument too, queued or performed" do
    travel_to(zone.local(2026, 11, 5, 12, 0)) do
      perform_enqueued_jobs { described_class.perform_later("2026-09") }
      expect(last_mail.subject).to eq("CDEL Reports from 2026-09-01 to 2026-09-30")
      described_class.perform_now("2026-08")
      expect(last_mail.subject).to eq("CDEL Reports from 2026-08-01 to 2026-08-31")
    end
  end

  it "covers a February of a leap year to its last day" do
    travel_to(zone.local(2026, 11, 5, 12, 0)) { described_class.perform_now(month: "2024-02") }
    expect(last_mail.subject).to eq("CDEL Reports from 2024-02-01 to 2024-02-29")
  end

  it "accepts the current month" do
    travel_to(zone.local(2026, 11, 5, 12, 0)) { described_class.perform_now(month: "2026-11") }
    expect(last_mail.subject).to eq("CDEL Reports from 2026-11-01 to 2026-11-30")
  end

  it "queues with a month as the rake and a console call do" do
    travel_to(zone.local(2026, 11, 5, 12, 0)) do
      perform_enqueued_jobs { described_class.perform_later(month: "2026-09") }
    end
    expect(last_mail.subject).to eq("CDEL Reports from 2026-09-01 to 2026-09-30")
  end

  describe "a month that cannot be reported" do
    around { |example| travel_to(zone.local(2026, 11, 5, 12, 0)) { example.run } }

    ["2026-8", "2026-13", "2026-00", "August", "2026/08", "2026-08-01", " 2026-08", "26-08"].each do |bad|
      it "refuses #{bad.inspect} with the expected format in the message, and sends nothing" do
        expect { described_class.perform_now(month: bad) }
          .to raise_error(described_class::InvalidMonth, /YYYY-MM/)
        expect(ActionMailer::Base.deliveries).to be_empty
      end
    end

    it "refuses a positional argument that is not a month, with the same message" do
      expect { described_class.perform_later("nope") }.to raise_error(described_class::InvalidMonth, /YYYY-MM/)
      expect { described_class.perform_later(5) }.to raise_error(described_class::InvalidMonth, /YYYY-MM/)
      expect { described_class.perform_now("2026-12") }.to raise_error(described_class::InvalidMonth, /future/)
      expect(enqueued_jobs).to be_empty
    end

    it "refuses a future month and says so" do
      expect { described_class.perform_now(month: "2026-12") }
        .to raise_error(described_class::InvalidMonth, /2026-12 is in the future/)
      expect { described_class.perform_now(month: "2027-01") }.to raise_error(described_class::InvalidMonth)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "refuses at queueing time, so nothing is left in the queue" do
      expect { described_class.perform_later(month: "nope") }.to raise_error(described_class::InvalidMonth)
      expect(enqueued_jobs).to be_empty
    end
  end

  describe "rake reports:send_cdel_report_to_sharepoint" do
    before do
      Rails.application.load_tasks unless Rake::Task.task_defined?("reports:send_cdel_report_to_sharepoint")
      Rake::Task["reports:send_cdel_report_to_sharepoint"].reenable
    end

    it "runs the job for last month without an argument" do
      expect(described_class).to receive(:perform_now).with(month: nil)
      Rake::Task["reports:send_cdel_report_to_sharepoint"].invoke
    end

    it "passes the YYYY-MM argument on" do
      travel_to(zone.local(2026, 11, 5, 12, 0)) { Rake::Task["reports:send_cdel_report_to_sharepoint"].invoke("2026-09") }
      expect(last_mail.subject).to eq("CDEL Reports from 2026-09-01 to 2026-09-30")
    end

    it "stops with the message on a bad month and sends nothing" do
      expect { Rake::Task["reports:send_cdel_report_to_sharepoint"].invoke("2026-13") }
        .to raise_error(SystemExit).and output(/Invalid month "2026-13"/).to_stderr
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
