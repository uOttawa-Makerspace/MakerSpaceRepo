# frozen_string_literal: true

require "rails_helper"

RSpec.describe HelpFilingSweepJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  def deliveries = ActionMailer::Base.deliveries

  def help_request(**attrs)
    Help.create!({ name: "Pat Visitor", email: "pat@example.test", subject: "Booking does not work",
                   comments: "I cannot book the room", source: Help::HELP_PAGE }.merge(attrs))
  end

  before do
    block_external_http!
    deliveries.clear
  end

  it "queues the job again for unfinished requests that have waited, and not for recent or finished ones" do
    waiting = help_request.tap { |h| h.update_columns(updated_at: 20.minutes.ago) }
    filed_only = help_request.tap { |h| h.update_columns(filed_at: 1.hour.ago, gh_issue_number: "5", updated_at: 1.hour.ago) }
    recent = help_request
    help_request.tap { |h| h.update_columns(filed_at: 1.hour.ago, mailed_at: 1.hour.ago, updated_at: 1.hour.ago) }
    legacy = help_request.tap { |h| h.update_columns(source: nil, updated_at: 1.hour.ago) } # saved before the job existed

    expect { described_class.perform_now }
      .to have_enqueued_job(HelpFilingJob).exactly(:twice)
    expect(HelpFilingJob).to have_been_enqueued.with(waiting.id)
    expect(HelpFilingJob).to have_been_enqueued.with(filed_only.id)
    expect(waiting.reload.resends).to eq(1)
    expect(legacy.reload.resends).to eq(0)
    expect(Help.unfinished).to contain_exactly(waiting, filed_only, recent)
  end

  it "files and mails a request whose job was never queued, once, and a second sweep queues nothing" do
    allow(HelpFilingJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue down")
    help = help_request
    expect(help.queue_filing).to be(false)
    allow(HelpFilingJob).to receive(:perform_later).and_call_original

    travel 16.minutes do
      perform_enqueued_jobs do
        described_class.perform_now
        described_class.perform_now
      end
    end

    expect(help.reload).to be_finished
    expect(help.gh_issue_number).to eq("111")
    expect(help.resends).to eq(1)
    expect(deliveries.map(&:to)).to eq([["uottawa.makerepo@gmail.com"]])
  end

  it "stops after the last resend and reports it" do
    help = help_request
    help.update_columns(resends: Help::MAX_RESENDS - 1, updated_at: 1.hour.ago)
    expect(Rails.error).to receive(:report)
      .with(an_instance_of(RuntimeError), hash_including(handled: true, context: hash_including(help_id: help.id)))
    expect { described_class.perform_now }.to have_enqueued_job(HelpFilingJob).with(help.id)

    help.update_columns(updated_at: 1.hour.ago)
    expect { described_class.perform_now }.not_to have_enqueued_job(HelpFilingJob)
    expect(help.reload.resends).to eq(Help::MAX_RESENDS)
  end

  it "counts the resend even when the queue cannot take the job" do
    help = help_request
    help.update_columns(updated_at: 1.hour.ago)
    allow(HelpFilingJob).to receive(:perform_later).and_raise(ActiveRecord::ConnectionNotEstablished)
    allow(Rails.error).to receive(:report)
    expect(described_class.perform_now).to eq(0)
    expect(help.reload.resends).to eq(1)
    expect(Rails.error).to have_received(:report).with(an_instance_of(ActiveRecord::ConnectionNotEstablished), hash_including(handled: true))
  end
end
