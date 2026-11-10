# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationMailDeliveryJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:attempts) { [] }

  before { ActionMailer::Base.deliveries.clear }

  # Makes the first deliveries raise the given errors, one per attempt, then lets the rest through.
  def fail_deliveries_with(*errors)
    queue = errors.dup
    allow_any_instance_of(Mail::TestMailer).to receive(:deliver!).and_wrap_original do |original, mail|
      attempts << mail.to
      error = queue.shift
      raise(error.is_a?(Class) ? error.new("refused") : error) if error

      original.call(mail)
    end
  end

  def send_welcome_mail
    MsrMailer.welcome_email(user).deliver_later
  end

  described_class::TRANSIENT_ERRORS.each do |error_class|
    it "tries again after #{error_class} and delivers the mail once the network is back" do
      fail_deliveries_with(error_class, error_class)

      perform_enqueued_jobs { send_welcome_mail }

      expect(attempts.size).to eq(3)
      expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[user.email]])
    end
  end

  it "tries again after the timeout errors Net::SMTP raises, which are Timeout::Error subclasses" do
    fail_deliveries_with(Net::OpenTimeout, Net::ReadTimeout)

    perform_enqueued_jobs { send_welcome_mail }

    expect(attempts.size).to eq(3)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end

  it "waits 30 seconds, 2 minutes, 10 minutes, 30 minutes, 1 hour and 2 hours between the seven runs" do
    fail_deliveries_with(*Array.new(6) { Net::ReadTimeout })
    now = Time.zone.parse("2026-11-10 12:00")
    waits = []

    travel_to(now) do
      send_welcome_mail
      6.times do
        perform_enqueued_jobs(only: described_class)
        waits << (enqueued_jobs.last[:at] - now.to_f).round
        expect(ActionMailer::Base.deliveries).to be_empty
      end
      perform_enqueued_jobs(only: described_class)
    end

    expect(waits).to eq([30, 120, 600, 1800, 3600, 7200])
    expect(attempts.size).to eq(7)
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[user.email]])
  end

  it "gives up after the seventh run and fails the job, so it is listed as failed" do
    fail_deliveries_with(*Array.new(10) { Net::ReadTimeout })

    expect { perform_enqueued_jobs { send_welcome_mail } }
      .to raise_error(Minitest::UnexpectedError) { |wrapper| expect(wrapper.error).to be_a(Net::ReadTimeout) }

    expect(attempts.size).to eq(7)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  [Net::SMTPFatalError, Net::SMTPSyntaxError, Net::SMTPAuthenticationError].each do |error_class|
    it "fails the job after #{error_class} on the first run, without trying again" do
      fail_deliveries_with(error_class)
      send_welcome_mail

      expect { perform_enqueued_jobs }.to raise_error(error_class)

      expect(attempts.size).to eq(1)
      expect(enqueued_jobs).to be_empty
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  it "fails the job on an error that is neither transient nor a refusal" do
    fail_deliveries_with(ArgumentError)
    send_welcome_mail

    expect { perform_enqueued_jobs }.to raise_error(ArgumentError)
    expect(attempts.size).to eq(1)
  end

  it "drops a mail whose record was deleted before the job ran" do
    send_welcome_mail
    user.destroy!

    expect { perform_enqueued_jobs }.not_to raise_error
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
