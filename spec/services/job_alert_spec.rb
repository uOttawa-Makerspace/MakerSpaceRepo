# frozen_string_literal: true

require "rails_helper"

RSpec.describe JobAlert do
  # The queue tables live in the queue database, which the test environment does not connect to; build the ones
  # used here inside the example's transaction (Postgres rolls the DDL back with it).
  before do
    conn = ActiveRecord::Base.connection
    conn.create_table(:solid_queue_jobs) do |t|
      t.string :class_name, null: false
      t.string :queue_name, null: false
      t.text :arguments
      t.string :active_job_id
      t.datetime :finished_at
      t.datetime :scheduled_at
      t.integer :priority, default: 0, null: false
      t.string :concurrency_key
      t.bigint :batch_id
      t.timestamps
    end
    conn.create_table(:solid_queue_failed_executions) do |t|
      t.bigint :job_id, null: false
      t.text :error
      t.datetime :created_at, null: false
    end
    conn.create_table(:solid_queue_scheduled_executions) do |t|
      t.bigint :job_id, null: false
      t.string :queue_name, null: false
      t.integer :priority, default: 0, null: false
      t.datetime :scheduled_at, null: false
      t.datetime :created_at, null: false
    end
    conn.create_table(:solid_queue_claimed_executions) do |t|
      t.bigint :job_id, null: false
      t.bigint :process_id
      t.datetime :created_at, null: false
    end
    queue_models.each(&:reset_column_information)
    Setting.maintenance_email = "maintenance@example.com"
    ActionMailer::Base.deliveries.clear
  end

  after { queue_models.each(&:reset_column_information) }

  let(:queue_models) do
    [SolidQueue::Job, SolidQueue::FailedExecution, SolidQueue::ScheduledExecution, SolidQueue::ClaimedExecution]
  end
  let(:now) { Time.zone.parse("2026-11-06 12:00") }
  let(:secret) { "student-jane@example.com" }

  def job(class_name: "SomeJob", queue_name: "default")
    # Inserted directly: creating a job through the model would also queue it for execution
    id = SolidQueue::Job.insert_all!([{ class_name: class_name, queue_name: queue_name,
                                        arguments: %({"arguments":["#{secret}"]}) }]).first["id"]
    SolidQueue::Job.find(id)
  end

  def fail_job(error: { exception_class: "RuntimeError", message: "boom", backtrace: [] }, at: now - 1.minute, **options)
    SolidQueue::FailedExecution.create!(job: job(**options), error: error, created_at: at)
  end

  def schedule(job, at)
    SolidQueue::ScheduledExecution.insert_all!([{ job_id: job.id, queue_name: job.queue_name, scheduled_at: at,
                                                  created_at: at }])
    job
  end

  def claim(job, at)
    SolidQueue::ClaimedExecution.insert_all!([{ job_id: job.id, created_at: at }])
    job
  end

  def run(at: now)
    described_class.new(now: at).run
  end

  def bodies
    ActionMailer::Base.deliveries.map { |mail| (mail.html_part || mail).body.decoded }
  end

  it "mails one alert for a failed execution and none when it runs again" do
    fail_job(class_name: "ExportJob", queue_name: "background")

    expect(run).to eq(1)
    expect(run).to eq(0)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    mail = ActionMailer::Base.deliveries.first
    expect(mail.to).to eq(["maintenance@example.com"])
    expect(bodies.first).to include("ExportJob", "background", "RuntimeError")
    expect(bodies.first).not_to include("boom")
  end

  it "mails a failure that arrives later without repeating the earlier one" do
    fail_job
    run
    fail_job(class_name: "OtherJob")

    expect(run).to eq(1)
    expect(bodies.last).to include("OtherJob")
    expect(bodies.last).not_to include("SomeJob")
  end

  it "mails nobody twice when two runs follow each other" do
    fail_job
    expect([run, run].sum).to eq(1)
  end

  it "reports a failed execution once even when the same job fails again as a new execution" do
    first = fail_job
    run
    first.destroy!
    SolidQueue::FailedExecution.create!(job: first.job, error: { exception_class: "RuntimeError", message: "again" },
                                        created_at: now)

    expect(run).to eq(1)
  end

  it "does not claim or mail anything while no maintenance address is set" do
    fail_job
    Setting.maintenance_email = nil

    expect(run).to eq(0)
    expect(ActionMailer::Base.deliveries).to be_empty
    Setting.maintenance_email = "maintenance@example.com"
    expect(run).to eq(1)
  end

  it "ignores failures older than the look-back" do
    fail_job(at: now - JobAlert::LOOKBACK - 1.minute)

    expect(run).to eq(0)
  end

  it "reports a scheduled execution that is overdue, but not one only just due or one in the future" do
    late = schedule(job(class_name: "LateJob"), now - JobAlert::SCHEDULED_OVERDUE_AFTER - 1.minute)
    schedule(job(class_name: "JustDueJob"), now - 1.minute)
    schedule(job(class_name: "FutureJob"), now + 1.hour)

    expect(run).to eq(1)
    expect(bodies.first).to include("LateJob", "scheduled", late.id.to_s)
    expect(bodies.first).not_to include("JustDueJob", "FutureJob")
    expect(run).to eq(0)
  end

  it "reports a claimed execution that has run too long, but not a recent one" do
    claim(job(class_name: "HungJob"), now - JobAlert::CLAIMED_OVERDUE_AFTER - 1.minute)
    claim(job(class_name: "BusyJob"), now - 5.minutes)

    expect(run).to eq(1)
    expect(bodies.first).to include("HungJob", "claimed")
    expect(bodies.first).not_to include("BusyJob")
  end

  it "keeps job arguments and the error message, even one holding an email address, out of the mail" do
    bounce = "550 5.1.1 <#{secret}>: Recipient address rejected"
    fail_job(error: { exception_class: "Net::SMTPFatalError", message: bounce, backtrace: ["x.rb:1 #{secret}"] })

    run
    expect(bodies.first).to include("Net::SMTPFatalError")
    expect(bodies.first).not_to include(secret, "Recipient address rejected")
    expect(ActionMailer::Base.deliveries.first.to_s).not_to include(secret)
  end

  it "mails at most one batch and the rest on the next run" do
    (JobAlert::BATCH + 3).times { fail_job }

    expect(run).to eq(JobAlert::BATCH)
    expect(run).to eq(3)
    expect(run).to eq(0)
  end

  it "gives the claims back when the mail cannot be sent, so the next run mails it" do
    fail_job
    allow(JobAlertMailer).to receive(:alert).and_raise(Net::SMTPFatalError, "down")

    expect { run }.to raise_error(Net::SMTPFatalError)
    allow(JobAlertMailer).to receive(:alert).and_call_original
    expect(run).to eq(1)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end
end
